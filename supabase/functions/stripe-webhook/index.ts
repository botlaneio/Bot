// Stripe webhook → BotLane account area.
//
// WHAT THIS EXISTS FOR
// A Marketplace buyer can pay today and receive nothing: there is no delivery
// mechanism. This function is that mechanism's first half. On payment it
// allowlists the buyer and records their order, so the account area has
// something to show them the moment they sign in.
//
// WHAT IT DELIBERATELY DOES NOT DO
// It does not create an auth user and it does not send email.
//
//   * Creating the user here means handling "already registered" on every
//     Stripe retry, and it forces one sign-in method on someone who may prefer
//     the other. Writing the customers row IS the invite — the auth trigger
//     (private.handle_new_auth_user) admits anyone whose email is in that
//     table, whether they arrive via Google or a magic link.
//   * Sending mail from a payment handler means a delivery failure looks like a
//     payment failure. Stripe already shows a post-purchase message and you
//     already promise a human follow-up within one business day.
//
// IDEMPOTENCY
// Stripe retries on any non-2xx, and will happily deliver the same event twice.
// Every write here is an upsert or an ON CONFLICT DO NOTHING keyed on a Stripe
// id, so replaying an event changes nothing.
//
// SECRETS (set these yourself; they are never in this file)
//   STRIPE_SECRET_KEY      — Stripe API key
//   STRIPE_WEBHOOK_SECRET  — signing secret from the Stripe webhook endpoint
//   SUPABASE_URL           — injected by Supabase
//   SUPABASE_SERVICE_ROLE_KEY — injected by Supabase. Bypasses RLS by design:
//                            the account area is read-only, so all writes come
//                            from here or from the operator.

import Stripe from "npm:stripe@^17";
import { createClient } from "npm:@supabase/supabase-js@^2";

/**
 * Config is read lazily, not at module load.
 *
 * Constructing the Stripe client at module scope with a missing key throws
 * during boot, and the platform reports that as an opaque WORKER_ERROR with a
 * 500 — which tells whoever is debugging nothing at all. Deferring it means a
 * missing secret produces a named, readable error instead.
 */
class ConfigError extends Error {}

function requireEnv(name: string): string {
    const value = Deno.env.get(name);
    if (!value) throw new ConfigError(`${name} is not set on this function`);
    return value;
}

let _stripe: Stripe | null = null;
function getStripe(): Stripe {
    // No apiVersion pin: the SDK's own default is the version it was built
    // against, and pinning to a string it does not know is its own failure mode.
    if (!_stripe) _stripe = new Stripe(requireEnv("STRIPE_SECRET_KEY"));
    return _stripe;
}

let _db: ReturnType<typeof createClient> | null = null;
function getDb() {
    if (!_db) {
        _db = createClient(requireEnv("SUPABASE_URL"), requireEnv("SUPABASE_SERVICE_ROLE_KEY"), {
            auth: { persistSession: false },
        });
    }
    return _db;
}

/** Find or create the customer row. Creating it is what grants sign-in. */
async function upsertCustomer(
    email: string,
    stripeCustomerId: string | null,
    name: string | null,
): Promise<string> {
    const normalised = email.trim().toLowerCase();

    const { data: existing, error: findErr } = await getDb()
        .from("customers")
        .select("id, stripe_customer_id, name")
        .ilike("email", normalised)
        .maybeSingle();
    if (findErr) throw findErr;

    if (existing) {
        // Backfill anything we did not know at invite time. Never overwrite a
        // name the operator has set by hand with Stripe's version.
        const patch: Record<string, unknown> = {};
        if (stripeCustomerId && !existing.stripe_customer_id) {
            patch.stripe_customer_id = stripeCustomerId;
        }
        if (name && !existing.name) patch.name = name;
        if (Object.keys(patch).length > 0) {
            const { error } = await getDb().from("customers").update(patch).eq("id", existing.id);
            if (error) throw error;
        }
        return existing.id as string;
    }

    const { data: created, error: insertErr } = await getDb()
        .from("customers")
        .insert({ email: normalised, stripe_customer_id: stripeCustomerId, name })
        .select("id")
        .single();
    if (insertErr) throw insertErr;

    console.log(`allowlisted new customer ${created.id} (${normalised})`);
    return created.id as string;
}

/**
 * The product slug, which ties a Stripe payment back to a Marketplace listing.
 *
 * Payment Link metadata is copied onto the Checkout Session, so the common path
 * is a single property read. The fallback expands the line item and reads the
 * product's own metadata, for orders created some other way.
 */
async function resolveSlug(session: Stripe.Checkout.Session): Promise<{ slug: string; name: string }> {
    const fromSession = session.metadata?.slug;

    const items = await getStripe().checkout.sessions.listLineItems(session.id, {
        limit: 1,
        expand: ["data.price.product"],
    });
    const product = items.data[0]?.price?.product as Stripe.Product | undefined;

    return {
        slug: fromSession ?? product?.metadata?.slug ?? "unknown",
        name: product?.name ?? items.data[0]?.description ?? "Unknown product",
    };
}

async function handleCheckoutCompleted(session: Stripe.Checkout.Session) {
    // `payment_status` guards against acting on an unpaid session, which is
    // possible with asynchronous payment methods.
    if (session.payment_status !== "paid") {
        console.log(`session ${session.id} not paid (${session.payment_status}), ignoring`);
        return;
    }

    const email = session.customer_details?.email;
    if (!email) {
        // Without an email there is nobody to give access to. Surface it rather
        // than silently dropping a paid order.
        throw new Error(`session ${session.id} has no customer email`);
    }

    const customerId = await upsertCustomer(
        email,
        typeof session.customer === "string" ? session.customer : null,
        session.customer_details?.name ?? null,
    );

    const { slug, name } = await resolveSlug(session);

    // ON CONFLICT DO NOTHING via ignoreDuplicates: the unique constraint on
    // stripe_checkout_session_id makes a replayed event a no-op.
    const { error: orderErr } = await getDb().from("orders").upsert(
        {
            customer_id: customerId,
            stripe_checkout_session_id: session.id,
            stripe_payment_intent_id:
                typeof session.payment_intent === "string" ? session.payment_intent : null,
            product_slug: slug,
            product_name: name,
            amount_cents: session.amount_total ?? 0,
            currency: session.currency ?? "usd",
            payment_status: "paid",
            fulfilment_status: "pending", // built to order; nothing ships automatically
            purchased_at: new Date((session.created ?? Date.now() / 1000) * 1000).toISOString(),
        },
        { onConflict: "stripe_checkout_session_id", ignoreDuplicates: true },
    );
    if (orderErr) throw orderErr;

    // Mirror the payment so the dashboard never calls Stripe to render.
    if (typeof session.payment_intent === "string") {
        const { error } = await getDb().from("payments").upsert(
            {
                customer_id: customerId,
                stripe_payment_intent_id: session.payment_intent,
                description: name,
                amount_cents: session.amount_total ?? 0,
                currency: session.currency ?? "usd",
                status: "paid",
                paid_at: new Date().toISOString(),
            },
            { onConflict: "stripe_payment_intent_id", ignoreDuplicates: true },
        );
        if (error) throw error;
    }

    console.log(`order recorded: ${slug} for customer ${customerId}`);
}

/** Keep the order honest when money goes back. */
async function handleChargeRefunded(charge: Stripe.Charge) {
    const pi = typeof charge.payment_intent === "string" ? charge.payment_intent : null;
    if (!pi) return;

    const fullyRefunded = charge.amount_refunded >= charge.amount;
    const status = fullyRefunded ? "refunded" : "partially_refunded";

    const { error: orderErr } = await getDb()
        .from("orders")
        .update({ payment_status: status })
        .eq("stripe_payment_intent_id", pi);
    if (orderErr) throw orderErr;

    if (fullyRefunded) {
        const { error } = await getDb()
            .from("payments")
            .update({ status: "refunded" })
            .eq("stripe_payment_intent_id", pi);
        if (error) throw error;
    }

    console.log(`refund applied to payment_intent ${pi} (${status})`);
}

/**
 * Service billing. Invoices are the mechanism for the $4,999 setup and the
 * $2,499/month maintenance — collection_method is send_invoice at net 14, so
 * these arrive as invoice events rather than checkout sessions.
 */
async function handleInvoice(invoice: Stripe.Invoice) {
    const stripeCustomerId =
        typeof invoice.customer === "string" ? invoice.customer : invoice.customer?.id;
    if (!stripeCustomerId) return;

    const { data: customer, error: findErr } = await getDb()
        .from("customers")
        .select("id")
        .eq("stripe_customer_id", stripeCustomerId)
        .maybeSingle();
    if (findErr) throw findErr;

    if (!customer) {
        // Service clients are onboarded by hand, so their customers row should
        // already exist with stripe_customer_id set. Loudly skip rather than
        // inventing a customer from an invoice.
        console.warn(`invoice ${invoice.id}: no customer row for ${stripeCustomerId}, skipping`);
        return;
    }

    const statusMap: Record<string, string> = {
        draft: "draft",
        open: "open",
        paid: "paid",
        void: "void",
        uncollectible: "uncollectible",
    };

    const { error } = await getDb().from("payments").upsert(
        {
            customer_id: customer.id,
            stripe_invoice_id: invoice.id,
            description: invoice.description ?? invoice.lines?.data[0]?.description ?? "Invoice",
            amount_cents: invoice.amount_due ?? 0,
            currency: invoice.currency ?? "usd",
            status: statusMap[invoice.status ?? "open"] ?? "open",
            period_start: invoice.period_start
                ? new Date(invoice.period_start * 1000).toISOString()
                : null,
            period_end: invoice.period_end
                ? new Date(invoice.period_end * 1000).toISOString()
                : null,
            due_at: invoice.due_date ? new Date(invoice.due_date * 1000).toISOString() : null,
            paid_at: invoice.status === "paid" ? new Date().toISOString() : null,
            hosted_invoice_url: invoice.hosted_invoice_url ?? null,
        },
        { onConflict: "stripe_invoice_id" },
    );
    if (error) throw error;

    console.log(`invoice ${invoice.id} mirrored as ${invoice.status}`);
}

Deno.serve(async (req: Request) => {
    if (req.method !== "POST") {
        return new Response("Method not allowed", { status: 405 });
    }

    // Preflight the configuration before anything else. Without this, a missing
    // secret surfaces inside the signature check below and gets reported as
    // "Invalid signature" — which sends you looking in exactly the wrong place.
    const required = [
        "STRIPE_SECRET_KEY",
        "STRIPE_WEBHOOK_SECRET",
        "SUPABASE_URL",
        "SUPABASE_SERVICE_ROLE_KEY",
    ];
    const missing = required.filter((n) => !Deno.env.get(n));
    if (missing.length > 0) {
        // Report every missing name at once, and echo back the NAMES (never the
        // values) of any Stripe-ish variables that are present. A trailing
        // space or wrong case is invisible in a dashboard and obvious here;
        // quoting makes stray whitespace visible.
        const present = Object.keys(Deno.env.toObject())
            .filter((k) => /stripe/i.test(k))
            .map((k) => JSON.stringify(k));
        console.error(`not configured. missing: ${missing.join(", ")} | stripe-ish present: ${present.join(", ") || "none"}`);
        return new Response(
            JSON.stringify({
                error: "not_configured",
                missing,
                stripe_names_present: present,
            }),
            { status: 500, headers: { "Content-Type": "application/json" } },
        );
    }

    const signature = req.headers.get("Stripe-Signature");
    if (!signature) {
        return new Response("Missing Stripe-Signature", { status: 400 });
    }

    // The RAW body is required — parsing it first breaks the signature.
    const raw = await req.text();

    let event: Stripe.Event;
    try {
        // constructEventAsync, not constructEvent: Deno's WebCrypto is async and
        // the synchronous variant throws here.
        event = await getStripe().webhooks.constructEventAsync(raw, signature, requireEnv("STRIPE_WEBHOOK_SECRET"));
    } catch (err) {
        console.error("signature verification failed:", err instanceof Error ? err.message : err);
        return new Response("Invalid signature", { status: 400 });
    }

    try {
        switch (event.type) {
            case "checkout.session.completed":
            case "checkout.session.async_payment_succeeded":
                await handleCheckoutCompleted(event.data.object as Stripe.Checkout.Session);
                break;

            case "charge.refunded":
                await handleChargeRefunded(event.data.object as Stripe.Charge);
                break;

            case "invoice.finalized":
            case "invoice.paid":
            case "invoice.payment_failed":
            case "invoice.voided":
                await handleInvoice(event.data.object as Stripe.Invoice);
                break;

            default:
                // Everything else is acknowledged so Stripe stops retrying it.
                console.log(`ignoring ${event.type}`);
        }
    } catch (err) {
        // Return 500 so Stripe retries. Losing a paid order is far worse than
        // processing the same event twice, and every write here is idempotent.
        console.error(`handler failed for ${event.type} (${event.id}):`, err);
        return new Response("Handler error", { status: 500 });
    }

    return new Response(JSON.stringify({ received: true }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
    });
});
