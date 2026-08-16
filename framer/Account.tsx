// BotLane customer account area.
//
// RUNTIME SOURCE IS FRAMER. This copy exists so the code is reviewable and
// versioned — Framer code files are not in git. If you change one, change both.
//
// ── WHY PLAIN fetch AND NOT @supabase/supabase-js ────────────────────────
// Framer code files cannot import each other, and importing an npm package
// from a CDN is an unknown in this project. Supabase is plain HTTP: PostgREST
// for queries, GoTrue for auth, a signing endpoint for storage. `fetch` removes
// the dependency question entirely at the cost of a little more code.
//
// ── WHY THE PUBLISHABLE KEY IS IN THIS FILE ──────────────────────────────
// It is designed to be public. It grants nothing on its own: every request is
// still evaluated by row-level security in Postgres. A signed-in customer can
// read their own rows and nobody else's, and cannot write anything at all,
// because no insert/update/delete policy exists for the `authenticated` role.
// That is why the anon key being visible does not matter here.
//
// ── WHAT THIS DELIBERATELY DOES NOT DO ───────────────────────────────────
// No sign-up. There is no public registration: an address can only sign in if
// the operator has already added it to `customers`, which the Stripe webhook
// does automatically on purchase. An uninvited address is rejected by a
// database trigger, not by this component.
//
// ── SUPABASE CONFIGURATION REQUIRED ──────────────────────────────────────
// Authentication → URL Configuration → Redirect URLs must include the published
// URL of the page holding this component, e.g. https://botlane.io/account.
// Without it the magic link will refuse to come back and the sign-in silently
// fails. This is the single most likely thing to be wrong.

import {
    useCallback,
    useEffect,
    useMemo,
    useState,
    type CSSProperties,
    type FormEvent,
    type ReactNode,
} from "react"
import { addPropertyControls, ControlType, useIsStaticRenderer } from "framer"

const DISPLAY = '"Geist Mono", ui-monospace, SFMono-Regular, Menlo, monospace'
const MONO = '"JetBrains Mono", ui-monospace, SFMono-Regular, Menlo, monospace'
const BODY = 'Inter, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif'

const STORAGE_KEY = "botlane.refresh_token"

interface Theme {
    surface: string
    border: string
    text: string
    muted: string
    accent: string
}

const DEFAULT_THEME: Theme = {
    surface: "rgb(17, 17, 17)",
    border: "rgb(26, 26, 26)",
    text: "rgb(240, 240, 240)",
    muted: "rgb(136, 136, 136)",
    accent: "rgb(0, 255, 136)",
}

const money = (cents: number, currency = "usd") =>
    new Intl.NumberFormat("en-US", {
        style: "currency",
        currency: currency.toUpperCase(),
        maximumFractionDigits: cents % 100 === 0 ? 0 : 2,
    }).format(cents / 100)

const date = (iso: string | null) =>
    iso
        ? new Date(iso).toLocaleDateString("en-US", { day: "numeric", month: "short", year: "numeric" })
        : "—"

// ---------------------------------------------------------------- types

interface Order {
    id: string
    product_slug: string
    product_name: string
    amount_cents: number
    currency: string
    payment_status: string
    fulfilment_status: string
    purchased_at: string
    delivered_at: string | null
}

interface Payment {
    id: string
    description: string | null
    amount_cents: number
    currency: string
    status: string
    due_at: string | null
    paid_at: string | null
    hosted_invoice_url: string | null
}

interface Engagement {
    id: string
    status: string
    status_note: string | null
    started_at: string
    sending_started_at: string | null
}

interface DocRow {
    id: string
    kind: string
    title: string
    storage_path: string
    created_at: string
}

interface Me {
    id: string
    email: string
    name: string | null
    company: string | null
}

// ------------------------------------------------------------ transport

function useApi(baseUrl: string, apiKey: string) {
    return useMemo(() => {
        const url = baseUrl.replace(/\/+$/, "")

        async function rest<T>(path: string, token: string): Promise<T> {
            const res = await fetch(`${url}/rest/v1/${path}`, {
                headers: {
                    apikey: apiKey,
                    Authorization: `Bearer ${token}`,
                    Accept: "application/json",
                },
            })
            if (!res.ok) throw new Error(`${res.status} ${await res.text()}`)
            return res.json()
        }

        return {
            url,
            rest,

            /** Ask GoTrue to email a one-time link back to `redirectTo`. */
            async sendMagicLink(email: string, redirectTo: string) {
                const res = await fetch(
                    `${url}/auth/v1/otp?redirect_to=${encodeURIComponent(redirectTo)}`,
                    {
                        method: "POST",
                        headers: { apikey: apiKey, "Content-Type": "application/json" },
                        body: JSON.stringify({ email, create_user: true }),
                    },
                )
                if (!res.ok) throw new Error(await res.text())
            },

            /** Exchange a stored refresh token for a fresh access token. */
            async refresh(refreshToken: string) {
                const res = await fetch(`${url}/auth/v1/token?grant_type=refresh_token`, {
                    method: "POST",
                    headers: { apikey: apiKey, "Content-Type": "application/json" },
                    body: JSON.stringify({ refresh_token: refreshToken }),
                })
                if (!res.ok) throw new Error(await res.text())
                return res.json() as Promise<{ access_token: string; refresh_token: string }>
            },

            /** Short-lived URL for a private document. */
            async signDocument(path: string, token: string) {
                const res = await fetch(`${url}/storage/v1/object/sign/documents/${path}`, {
                    method: "POST",
                    headers: {
                        apikey: apiKey,
                        Authorization: `Bearer ${token}`,
                        "Content-Type": "application/json",
                    },
                    body: JSON.stringify({ expiresIn: 120 }),
                })
                if (!res.ok) throw new Error(await res.text())
                const { signedURL } = (await res.json()) as { signedURL: string }
                return `${url}/storage/v1${signedURL}`
            },
        }
    }, [baseUrl, apiKey])
}

// ------------------------------------------------------------------- ui

const label = (t: Theme) => ({
    fontFamily: MONO,
    fontSize: 12,
    letterSpacing: "0.06em",
    textTransform: "uppercase" as const,
    color: t.muted,
})

function Panel({ t, children }: { t: Theme; children: ReactNode }) {
    return (
        <div
            style={{
                display: "flex",
                flexDirection: "column",
                gap: 16,
                padding: 24,
                borderRadius: 16,
                border: `1px solid ${t.border}`,
                background: t.surface,
            }}
        >
            {children}
        </div>
    )
}

function Row({
    t,
    left,
    right,
    sub,
}: {
    t: Theme
    left: string
    right?: string
    sub?: ReactNode
}) {
    return (
        <div
            style={{
                display: "flex",
                flexDirection: "column",
                gap: 4,
                paddingBottom: 14,
                borderBottom: `1px solid ${t.border}`,
            }}
        >
            <div style={{ display: "flex", justifyContent: "space-between", gap: 16, flexWrap: "wrap" }}>
                <span style={{ fontFamily: BODY, fontSize: 15, color: t.text }}>{left}</span>
                {right ? (
                    <span style={{ fontFamily: DISPLAY, fontSize: 15, color: t.text, whiteSpace: "nowrap" }}>
                        {right}
                    </span>
                ) : null}
            </div>
            {sub ? <div style={{ ...label(t), textTransform: "none" }}>{sub}</div> : null}
        </div>
    )
}

/** Fulfilment is the thing a buyer actually wants to know. */
function statusText(o: Order): string {
    if (o.payment_status === "refunded") return "Refunded"
    if (o.fulfilment_status === "delivered") return `Delivered ${date(o.delivered_at)}`
    if (o.fulfilment_status === "in_progress") return "Being built"
    if (o.fulfilment_status === "cancelled") return "Cancelled"
    return "Built to order — we will confirm scope and lead time by email"
}

export default function Account(props: {
    supabaseUrl: string
    publishableKey: string
    surface: string
    border: string
    text: string
    muted: string
    accent: string
    style?: CSSProperties
}) {
    const t: Theme = {
        surface: props.surface || DEFAULT_THEME.surface,
        border: props.border || DEFAULT_THEME.border,
        text: props.text || DEFAULT_THEME.text,
        muted: props.muted || DEFAULT_THEME.muted,
        accent: props.accent || DEFAULT_THEME.accent,
    }
    const isStatic = useIsStaticRenderer()
    const api = useApi(props.supabaseUrl, props.publishableKey)

    const [token, setToken] = useState<string | null>(null)
    const [booting, setBooting] = useState(true)
    const [email, setEmail] = useState("")
    const [sent, setSent] = useState(false)
    const [error, setError] = useState<string | null>(null)
    const [busy, setBusy] = useState(false)

    const [me, setMe] = useState<Me | null>(null)
    const [orders, setOrders] = useState<Order[]>([])
    const [payments, setPayments] = useState<Payment[]>([])
    const [engagement, setEngagement] = useState<Engagement | null>(null)
    const [docs, setDocs] = useState<DocRow[]>([])

    // Restore a session: first from the magic-link hash, then from storage.
    useEffect(() => {
        if (isStatic) {
            setBooting(false)
            return
        }
        let cancelled = false

        ;(async () => {
            try {
                const hash = new URLSearchParams(window.location.hash.replace(/^#/, ""))
                const access = hash.get("access_token")
                const refresh = hash.get("refresh_token")

                if (access && refresh) {
                    window.localStorage.setItem(STORAGE_KEY, refresh)
                    // Strip the tokens from the address bar so they are not
                    // shared, bookmarked or leaked in a referrer.
                    window.history.replaceState({}, "", window.location.pathname + window.location.search)
                    if (!cancelled) setToken(access)
                    return
                }

                const stored = window.localStorage.getItem(STORAGE_KEY)
                if (stored) {
                    const next = await api.refresh(stored)
                    window.localStorage.setItem(STORAGE_KEY, next.refresh_token)
                    if (!cancelled) setToken(next.access_token)
                }
            } catch {
                // An expired or revoked refresh token just means signed out.
                window.localStorage.removeItem(STORAGE_KEY)
            } finally {
                if (!cancelled) setBooting(false)
            }
        })()

        return () => {
            cancelled = true
        }
    }, [api, isStatic])

    // Load everything the account area shows. RLS scopes each query to this
    // customer, so no filter is needed here — and none could be trusted anyway.
    useEffect(() => {
        if (!token) return
        let cancelled = false

        ;(async () => {
            try {
                const [meRows, orderRows, paymentRows, engagementRows, docRows] = await Promise.all([
                    api.rest<Me[]>("customers?select=id,email,name,company", token),
                    api.rest<Order[]>("orders?select=*&order=purchased_at.desc", token),
                    api.rest<Payment[]>("payments?select=*&order=created_at.desc", token),
                    api.rest<Engagement[]>("engagements?select=*&order=started_at.desc&limit=1", token),
                    api.rest<DocRow[]>("documents?select=*&order=created_at.desc", token),
                ])
                if (cancelled) return
                setMe(meRows[0] ?? null)
                setOrders(orderRows)
                setPayments(paymentRows)
                setEngagement(engagementRows[0] ?? null)
                setDocs(docRows)
            } catch (e) {
                if (!cancelled) setError(e instanceof Error ? e.message : "Could not load your account.")
            }
        })()

        return () => {
            cancelled = true
        }
    }, [api, token])

    const submit = useCallback(
        async (e: FormEvent) => {
            e.preventDefault()
            setError(null)
            setBusy(true)
            try {
                await api.sendMagicLink(email.trim(), window.location.href.split("#")[0])
                setSent(true)
            } catch {
                // GoTrue reports the invite-gate rejection as a generic database
                // error, so the specific cause cannot be shown. This is the
                // overwhelmingly likely reason, so say it plainly.
                setError(
                    "We could not send a link to that address. Accounts exist only for customers — if you have bought something, use the email you paid with.",
                )
            } finally {
                setBusy(false)
            }
        },
        [api, email],
    )

    const signOut = useCallback(() => {
        window.localStorage.removeItem(STORAGE_KEY)
        setToken(null)
        setMe(null)
        setOrders([])
        setPayments([])
        setEngagement(null)
        setDocs([])
        setSent(false)
    }, [])

    const openDoc = useCallback(
        async (path: string) => {
            if (!token) return
            try {
                const url = await api.signDocument(path, token)
                window.open(url, "_blank", "noopener")
            } catch {
                setError("That document could not be opened. Email sales@botlane.io.")
            }
        },
        [api, token],
    )

    const nextDue = useMemo(
        () =>
            payments
                .filter((p) => p.status === "open" && p.due_at)
                .sort((a, b) => (a.due_at! < b.due_at! ? -1 : 1))[0] ?? null,
        [payments],
    )

    const shell: CSSProperties = {
        display: "flex",
        flexDirection: "column",
        gap: 24,
        width: "100%",
        fontFamily: BODY,
        ...props.style,
    }

    if (booting) {
        return (
            <div style={shell}>
                <span style={label(t)}>Loading…</span>
            </div>
        )
    }

    // ------------------------------------------------------- signed out
    if (!token) {
        return (
            <div style={{ ...shell, maxWidth: 460 }}>
                <span style={label(t)}>Your account</span>
                <h2
                    style={{
                        margin: 0,
                        fontFamily: DISPLAY,
                        fontWeight: 500,
                        fontSize: 28,
                        letterSpacing: "-0.03em",
                        color: t.text,
                    }}
                >
                    {sent ? "Check your email." : "Sign in."}
                </h2>

                {sent ? (
                    <p style={{ margin: 0, fontSize: 15, lineHeight: "1.6em", color: t.muted }}>
                        A sign-in link is on its way to{" "}
                        <span style={{ color: t.text }}>{email}</span>. It expires shortly, so use it
                        soon. Nothing to remember and no password to set.
                    </p>
                ) : (
                    <>
                        <p style={{ margin: 0, fontSize: 15, lineHeight: "1.6em", color: t.muted }}>
                            Enter the email you bought with and we will send a sign-in link. Accounts
                            are created for customers only — there is no sign-up.
                        </p>
                        <form onSubmit={submit} style={{ display: "flex", flexDirection: "column", gap: 12 }}>
                            <input
                                type="email"
                                required
                                value={email}
                                onChange={(e) => setEmail(e.target.value)}
                                placeholder="you@yourfirm.com"
                                style={{
                                    minHeight: 44,
                                    boxSizing: "border-box",
                                    padding: "0 14px",
                                    borderRadius: 8,
                                    border: `1px solid ${t.border}`,
                                    background: t.surface,
                                    color: t.text,
                                    fontFamily: BODY,
                                    fontSize: 15,
                                    outline: "none",
                                }}
                            />
                            <button
                                type="submit"
                                disabled={busy}
                                style={{
                                    minHeight: 44,
                                    borderRadius: 8,
                                    border: "none",
                                    background: t.accent,
                                    color: "rgb(8, 8, 8)",
                                    fontFamily: BODY,
                                    fontWeight: 500,
                                    fontSize: 15,
                                    cursor: busy ? "default" : "pointer",
                                    opacity: busy ? 0.6 : 1,
                                }}
                            >
                                {busy ? "Sending…" : "Email me a link"}
                            </button>
                        </form>
                    </>
                )}

                {error ? (
                    <p style={{ margin: 0, fontSize: 14, lineHeight: "1.6em", color: t.muted }}>{error}</p>
                ) : null}
            </div>
        )
    }

    // --------------------------------------------------------- signed in
    return (
        <div style={shell}>
            <div style={{ display: "flex", justifyContent: "space-between", gap: 16, flexWrap: "wrap" }}>
                <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
                    <span style={label(t)}>Your account</span>
                    <h2
                        style={{
                            margin: 0,
                            fontFamily: DISPLAY,
                            fontWeight: 500,
                            fontSize: 28,
                            letterSpacing: "-0.03em",
                            color: t.text,
                        }}
                    >
                        {me?.company || me?.name || me?.email || "Welcome"}
                    </h2>
                </div>
                <button
                    onClick={signOut}
                    style={{
                        alignSelf: "flex-start",
                        minHeight: 36,
                        padding: "0 14px",
                        borderRadius: 8,
                        border: `1px solid ${t.border}`,
                        background: "transparent",
                        color: t.text,
                        fontFamily: BODY,
                        fontSize: 14,
                        cursor: "pointer",
                    }}
                >
                    Sign out
                </button>
            </div>

            {error ? (
                <p style={{ margin: 0, fontSize: 14, color: t.muted }}>{error}</p>
            ) : null}

            {engagement ? (
                <Panel t={t}>
                    <span style={label(t)}>Outbound infrastructure</span>
                    <span style={{ fontFamily: DISPLAY, fontSize: 22, color: t.accent }}>
                        {engagement.status === "sending"
                            ? "Running"
                            : engagement.status === "warming"
                              ? "Warming the sending domain"
                              : engagement.status === "setup"
                                ? "In setup"
                                : engagement.status === "paused"
                                  ? "Paused"
                                  : "Ended"}
                    </span>
                    {engagement.status_note ? (
                        <p style={{ margin: 0, fontSize: 15, lineHeight: "1.6em", color: t.muted }}>
                            {engagement.status_note}
                        </p>
                    ) : null}
                    <Row t={t} left="Started" right={date(engagement.started_at)} />
                    <Row t={t} left="Sending since" right={date(engagement.sending_started_at)} />
                </Panel>
            ) : null}

            {nextDue ? (
                <Panel t={t}>
                    <span style={label(t)}>Next payment due</span>
                    <div style={{ display: "flex", alignItems: "baseline", gap: 10, flexWrap: "wrap" }}>
                        <span style={{ fontFamily: DISPLAY, fontSize: 30, color: t.text }}>
                            {money(nextDue.amount_cents, nextDue.currency)}
                        </span>
                        <span style={{ ...label(t), textTransform: "none" }}>
                            due {date(nextDue.due_at)}
                        </span>
                    </div>
                    {nextDue.hosted_invoice_url ? (
                        <a
                            href={nextDue.hosted_invoice_url}
                            target="_blank"
                            rel="noopener"
                            style={{ color: t.accent, fontSize: 15, textDecoration: "none" }}
                        >
                            View and pay invoice →
                        </a>
                    ) : null}
                </Panel>
            ) : null}

            <Panel t={t}>
                <span style={label(t)}>Automations</span>
                {orders.length === 0 ? (
                    <p style={{ margin: 0, fontSize: 15, color: t.muted }}>Nothing here yet.</p>
                ) : (
                    orders.map((o) => (
                        <Row
                            key={o.id}
                            t={t}
                            left={o.product_name}
                            right={money(o.amount_cents, o.currency)}
                            sub={`${statusText(o)} · bought ${date(o.purchased_at)}`}
                        />
                    ))
                )}
            </Panel>

            {payments.length > 0 ? (
                <Panel t={t}>
                    <span style={label(t)}>Payments</span>
                    {payments.map((p) => (
                        <Row
                            key={p.id}
                            t={t}
                            left={p.description || "Payment"}
                            right={money(p.amount_cents, p.currency)}
                            sub={
                                p.hosted_invoice_url ? (
                                    <a
                                        href={p.hosted_invoice_url}
                                        target="_blank"
                                        rel="noopener"
                                        style={{ color: t.accent, textDecoration: "none" }}
                                    >
                                        {p.status === "paid" ? `Paid ${date(p.paid_at)}` : p.status} · invoice →
                                    </a>
                                ) : p.status === "paid" ? (
                                    `Paid ${date(p.paid_at)}`
                                ) : (
                                    p.status
                                )
                            }
                        />
                    ))}
                </Panel>
            ) : null}

            {docs.length > 0 ? (
                <Panel t={t}>
                    <span style={label(t)}>Documents</span>
                    {docs.map((d) => (
                        <div
                            key={d.id}
                            style={{
                                display: "flex",
                                justifyContent: "space-between",
                                alignItems: "center",
                                gap: 16,
                                paddingBottom: 14,
                                borderBottom: `1px solid ${t.border}`,
                            }}
                        >
                            <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
                                <span style={{ fontSize: 15, color: t.text }}>{d.title}</span>
                                <span style={{ ...label(t), textTransform: "none" }}>
                                    {d.kind} · {date(d.created_at)}
                                </span>
                            </div>
                            <button
                                onClick={() => openDoc(d.storage_path)}
                                style={{
                                    border: `1px solid ${t.border}`,
                                    background: "transparent",
                                    color: t.accent,
                                    borderRadius: 8,
                                    minHeight: 36,
                                    padding: "0 14px",
                                    fontFamily: BODY,
                                    fontSize: 14,
                                    cursor: "pointer",
                                    whiteSpace: "nowrap",
                                }}
                            >
                                Open
                            </button>
                        </div>
                    ))}
                </Panel>
            ) : null}

            <p style={{ margin: 0, fontSize: 14, lineHeight: "1.6em", color: t.muted }}>
                Anything here wrong or missing? Email{" "}
                <span style={{ color: t.text }}>sales@botlane.io</span> and a person will answer.
            </p>
        </div>
    )
}

addPropertyControls(Account, {
    supabaseUrl: {
        type: ControlType.String,
        title: "Supabase URL",
        defaultValue: "https://nekribxexmpmpzefcpvn.supabase.co",
    },
    publishableKey: {
        type: ControlType.String,
        title: "Publishable key",
        defaultValue: "sb_publishable_Cv-m1k1cjb4V4FLIC4T6kA_CE5q9ujm",
        description: "Publishable (anon) key. Safe in the browser — RLS does the enforcing.",
    },
    surface: { type: ControlType.Color, title: "Surface", defaultValue: DEFAULT_THEME.surface },
    border: { type: ControlType.Color, title: "Border", defaultValue: DEFAULT_THEME.border },
    text: { type: ControlType.Color, title: "Text", defaultValue: DEFAULT_THEME.text },
    muted: { type: ControlType.Color, title: "Muted", defaultValue: DEFAULT_THEME.muted },
    accent: { type: ControlType.Color, title: "Accent", defaultValue: DEFAULT_THEME.accent },
})
