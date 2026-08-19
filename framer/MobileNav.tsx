// BotLane mobile navigation — slide-in panel.
//
// A copy is committed at framer/MobileNav.tsx. Framer is the runtime; change
// one, change both.
//
// Replaces the full-screen dropdown. The panel comes in from the right at ~75%
// width, over a blurred backdrop, so the page stays visible behind it. A menu
// that covers everything reads as a page change; one that covers three quarters
// reads as a layer you can dismiss — which is what a nav actually is.
//
// ── BEHAVIOUR THAT IS EASY TO FORGET AND OBVIOUS WHEN MISSING ────────────
//   * Escape closes it.
//   * Clicking the backdrop closes it.
//   * Following a link closes it, so returning via the back button does not
//     land on an open menu.
//   * Body scroll is locked while open, and the scroll position is restored on
//     close rather than jumping to the top.
//   * `prefers-reduced-motion` drops the slide and the stagger, keeping only a
//     fade. Motion is decoration; access to navigation is not.
//   * Focus moves into the panel on open and returns to the trigger on close.
//
// ── WHY THE OVERLAY IS MOVED TO document.body BY HAND ────────────────────
// The navbar sits inside an ancestor carrying a CSS transform. A transformed
// ancestor becomes the containing block for `position: fixed` descendants, so
// the panel anchored to that div rather than the viewport and left a sliver of
// itself on screen while closed. No CSS fixes that from inside the subtree —
// the overlay has to leave it.
//
// Measured 2026-08-17 on the published site, with the relocation removed: the
// panel reported `position: fixed` yet came back 420x72, not pinned to the
// right edge and not full height — clipped by the navbar's own `overflow:
// clip` rather than filling the viewport. With the relocation in place it
// resolves against the viewport as intended. This is not theoretical.
//
// The obvious tool is createPortal, but **importing react-dom in a Framer code
// file makes the whole component render nothing**, with no console error: the
// container mounts 0x0 and empty. So the overlay is relocated imperatively
// instead — React still owns and updates the nodes, they simply live somewhere
// else in the document. The effect moves the wrapper back before unmount so
// React removes it from the parent it expects.
//
// ── HISTORY: THE BUG THAT WAS NEVER IN THIS FILE ─────────────────────────
// This component was once bisected down to a useState-only stub because it
// "rendered nothing" on mobile, across four publish cycles. It was never
// broken. The instance inside the NavBar's `Mobile_Light` variant had
// visibility off, and a hidden Framer node emits no DOM at all — so every
// reading was measuring that flag, not this code.
//
// Confirmed 2026-08-17: at desktop width, where the same instance IS visible,
// this build rendered its trigger and opened its panel correctly. If it ever
// appears to render nothing again, check the node's visibility in every
// variant BEFORE editing anything here. Note also that Framer's MCP API
// cannot see into or write children of a replica ("Cannot set parent to a
// replica node"), so variant contents must be inspected in the editor.
//
// ── FRAMER ───────────────────────────────────────────────────────────────
// `previewOpen` forces the open state on the canvas so the panel can be
// designed without clicking. It is ignored on the published site.

import {
    useCallback,
    useEffect,
    useId,
    useRef,
    useState,
    type CSSProperties,
} from "react"
import { addPropertyControls, ControlType, RenderTarget } from "framer"

const DISPLAY = '"Geist Mono", ui-monospace, SFMono-Regular, Menlo, monospace'
const MONO = '"JetBrains Mono", ui-monospace, SFMono-Regular, Menlo, monospace'
const BODY = 'Inter, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif'

// Long, low-overshoot easing. Reads as weight rather than bounce, which is the
// difference between "premium" and "playful".
const EASE = "cubic-bezier(0.32, 0.72, 0, 1)"

interface Item {
    label: string
    link: string
}

interface Props {
    items: Item[]
    ctaLabel: string
    ctaLink: string
    widthPercent: number
    maxWidth: number
    hideAbove: number
    eyebrow: string
    footnote: string
    previewOpen: boolean
    surface: string
    border: string
    text: string
    muted: string
    accent: string
    style?: CSSProperties
}

function rgba(input: string, alpha: number) {
    const nums = (input || "").match(/[\d.]+/g)
    if (nums && nums.length >= 3) return `rgba(${nums[0]}, ${nums[1]}, ${nums[2]}, ${alpha})`
    return input
}

/**
 * MobileNav
 *
 * @framerIntrinsicWidth 44
 * @framerIntrinsicHeight 44
 *
 * @framerSupportedLayoutWidth fixed
 * @framerSupportedLayoutHeight fixed
 */
export default function MobileNav(props: Props) {
    const {
        items = [],
        ctaLabel,
        ctaLink,
        widthPercent,
        maxWidth,
        hideAbove,
        eyebrow,
        footnote,
        previewOpen,
        surface,
        border,
        text,
        muted,
        accent,
    } = props

    // Canvas only. The published site never reads this — routing runtime state
    // through a static-render check kept this panel shut on the live site.
    const onCanvas = RenderTarget.current() === RenderTarget.canvas
    const [open, setOpen] = useState(false)
    const [reduced, setReduced] = useState(false)
    const panelRef = useRef<HTMLDivElement | null>(null)
    const triggerRef = useRef<HTMLButtonElement | null>(null)
    const scrollY = useRef(0)
    const cls = `mnav-${useId().replace(/:/g, "")}`

    // On the canvas the panel is shown so it can be designed; on the published
    // site `previewOpen` is ignored entirely.
    const shown = onCanvas ? previewOpen : open

    useEffect(() => {
        if (typeof window === "undefined") return
        const mq = window.matchMedia("(prefers-reduced-motion: reduce)")
        const apply = () => setReduced(mq.matches)
        apply()
        mq.addEventListener?.("change", apply)
        return () => mq.removeEventListener?.("change", apply)
    }, [])

    // Escape to close.
    useEffect(() => {
        if (!open) return
        const onKey = (e: KeyboardEvent) => {
            if (e.key === "Escape") setOpen(false)
        }
        window.addEventListener("keydown", onKey)
        return () => window.removeEventListener("keydown", onKey)
    }, [open])

    // Lock body scroll, and restore the exact position afterwards. Setting
    // overflow alone lets the page jump to the top on some browsers.
    useEffect(() => {
        if (typeof document === "undefined" || !open) return
        const body = document.body
        scrollY.current = window.scrollY
        body.style.position = "fixed"
        body.style.top = `-${scrollY.current}px`
        body.style.left = "0"
        body.style.right = "0"
        body.style.overflow = "hidden"
        return () => {
            body.style.position = ""
            body.style.top = ""
            body.style.left = ""
            body.style.right = ""
            body.style.overflow = ""
            window.scrollTo(0, scrollY.current)
        }
    }, [open])

    // Move focus in on open, hand it back to the trigger on close. The wasOpen
    // guard stops the trigger from grabbing focus on the first (closed) render.
    const wasOpen = useRef(false)
    useEffect(() => {
        if (onCanvas) return
        if (open) panelRef.current?.focus()
        else if (wasOpen.current) triggerRef.current?.focus?.()
        wasOpen.current = open
    }, [open])

    const overlayRef = useRef<HTMLDivElement | null>(null)

    // Relocate the overlay to <body>, escaping the transformed ancestor.
    // Cleanup returns it so React unmounts it from the parent it expects.
    useEffect(() => {
        if (onCanvas || typeof document === "undefined") return
        const el = overlayRef.current
        if (!el) return
        const home = el.parentElement
        document.body.appendChild(el)
        return () => {
            if (home && el.parentElement !== home) home.appendChild(el)
        }
    }, [onCanvas])

    const close = useCallback(() => setOpen(false), [])

    const panelWidth = `min(${widthPercent}%, ${maxWidth}px)`
    const slide = reduced ? "none" : `transform 520ms ${EASE}`

    const overlay = (
        <div ref={overlayRef}>
        {/* Backdrop. Blurred rather than merely dark, so the page reads as
            still there — the panel is a layer, not a new screen. */}
        <div
            className={`${cls}-layer`}
            onClick={close}
            aria-hidden="true"
            style={{
                position: "fixed",
                inset: 0,
                zIndex: 9998,
                background: "rgba(0, 0, 0, 0.55)",
                backdropFilter: "blur(10px) saturate(120%)",
                WebkitBackdropFilter: "blur(10px) saturate(120%)",
                opacity: shown ? 1 : 0,
                pointerEvents: shown ? "auto" : "none",
                transition: `opacity 420ms ${EASE}`,
            }}
        />

        <div
            className={`${cls}-layer`}
            ref={panelRef}
            role="dialog"
            aria-modal="true"
            aria-label="Navigation"
            tabIndex={-1}
            style={{
                position: "fixed",
                top: 0,
                right: 0,
                bottom: 0,
                width: panelWidth,
                zIndex: 9999,
                display: "flex",
                flexDirection: "column",
                boxSizing: "border-box",
                padding: "32px 28px 28px",
                background: surface,
                // A hairline of accent on the leading edge, and a long
                // shadow so the panel sits above the page rather than in it.
                borderLeft: `1px solid ${rgba(accent, 0.18)}`,
                boxShadow: shown ? "-32px 0 80px rgba(0, 0, 0, 0.55)" : "none",
                transform: shown ? "translateX(0)" : "translateX(101%)",
                transition: slide,
                outline: "none",
                overflowY: "auto",
            }}
        >
            {/* A faint accent wash at the top edge. Enough to catch light,
                not enough to notice as a gradient. */}
            <div
                aria-hidden="true"
                style={{
                    position: "absolute",
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 180,
                    pointerEvents: "none",
                    background: `linear-gradient(180deg, ${rgba(accent, 0.06)} 0%, ${rgba(accent, 0)} 100%)`,
                }}
            />

            {/* Header row: label on the left, close on the right.
                The navbar trigger also turns into an X, but it sits inside the
                page's stacking context while this panel is mounted on <body>,
                so on a phone the trigger is painted underneath the panel and
                cannot be reached once open. The panel needs its own close. */}
            <div
                style={{
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "space-between",
                    gap: 12,
                    marginBottom: 36,
                    opacity: shown ? 1 : 0,
                    transition: reduced ? "none" : `opacity 300ms ${EASE} 120ms`,
                }}
            >
                <span
                    style={{
                        fontFamily: MONO,
                        fontSize: 11,
                        letterSpacing: "0.14em",
                        textTransform: "uppercase",
                        color: muted,
                    }}
                >
                    {eyebrow}
                </span>

                <button
                    onClick={close}
                    aria-label="Close menu"
                    style={{
                        position: "relative",
                        width: 44,
                        height: 44,
                        marginRight: -10,
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        background: "transparent",
                        border: "none",
                        cursor: "pointer",
                        padding: 0,
                        flexShrink: 0,
                    }}
                >
                    <span
                        style={{
                            position: "absolute",
                            width: 18,
                            height: 1.5,
                            borderRadius: 2,
                            background: text,
                            transform: "rotate(45deg)",
                        }}
                    />
                    <span
                        style={{
                            position: "absolute",
                            width: 18,
                            height: 1.5,
                            borderRadius: 2,
                            background: text,
                            transform: "rotate(-45deg)",
                        }}
                    />
                </button>
            </div>

            <nav style={{ display: "flex", flexDirection: "column", flex: "1 1 auto" }}>
                {items.map((item, i) => (
                    <a
                        key={`${item.label}-${i}`}
                        href={item.link}
                        onClick={close}
                        style={{
                            display: "block",
                            padding: "18px 0",
                            borderBottom: `1px solid ${border}`,
                            fontFamily: DISPLAY,
                            fontSize: 20,
                            letterSpacing: "-0.02em",
                            color: text,
                            textDecoration: "none",
                            // Staggered entrance. Each item is 55ms behind
                            // the last, which reads as the panel settling
                            // rather than as items animating individually.
                            opacity: shown ? 1 : 0,
                            transform: shown || reduced ? "translateX(0)" : "translateX(18px)",
                            transition: reduced
                                ? `opacity 200ms linear`
                                : `opacity 420ms ${EASE} ${140 + i * 55}ms, transform 420ms ${EASE} ${140 + i * 55}ms`,
                        }}
                    >
                        {item.label}
                    </a>
                ))}
            </nav>

            {ctaLabel ? (
                <a
                    href={ctaLink}
                    onClick={close}
                    style={{
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        minHeight: 52,
                        marginTop: 28,
                        borderRadius: 10,
                        background: accent,
                        color: "rgb(8, 8, 8)",
                        fontFamily: BODY,
                        fontWeight: 500,
                        fontSize: 15,
                        textDecoration: "none",
                        opacity: shown ? 1 : 0,
                        transform: shown || reduced ? "translateY(0)" : "translateY(10px)",
                        transition: reduced
                            ? "opacity 200ms linear"
                            : `opacity 420ms ${EASE} ${180 + items.length * 55}ms, transform 420ms ${EASE} ${180 + items.length * 55}ms`,
                    }}
                >
                    {ctaLabel}
                </a>
            ) : null}

            {footnote ? (
                <span
                    style={{
                        marginTop: 18,
                        fontFamily: MONO,
                        fontSize: 11,
                        lineHeight: "1.5em",
                        letterSpacing: "0.04em",
                        color: muted,
                        opacity: shown ? 1 : 0,
                        transition: reduced
                            ? "none"
                            : `opacity 420ms ${EASE} ${220 + items.length * 55}ms`,
                    }}
                >
                    {footnote}
                </span>
            ) : null}
        </div>
        </div>
    )


    return (
        <>
            {/*
                The component hides its own trigger above `hideAbove`, so one
                instance can sit in the NavBar and work at every width without
                relying on Framer variants. Change `hideAbove` to move where the
                hamburger appears — currently 1200px, which is why it shows on
                laptops that report under that.
            */}
            <style>{`
                @media (min-width: ${hideAbove}px) {
                    .${cls}-trigger { display: none !important; }
                    .${cls}-layer { display: none !important; }
                }
            `}</style>

            {/* Trigger. Two bars that cross into an X — fewer moving parts than
                three, and the transition reads more deliberately. */}
            <button
                className={`${cls}-trigger`}
                ref={triggerRef}
                aria-label={shown ? "Close menu" : "Open menu"}
                aria-expanded={shown}
                onClick={() => setOpen((v) => !v)}
                style={{
                    position: "relative",
                    width: 44,
                    height: 44,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    background: "transparent",
                    border: "none",
                    cursor: "pointer",
                    padding: 0,
                    zIndex: 10001,
                    ...props.style,
                }}
            >
                <span
                    style={{
                        position: "absolute",
                        width: 20,
                        height: 1.5,
                        borderRadius: 2,
                        background: text,
                        transition: reduced ? "none" : `transform 380ms ${EASE}`,
                        transform: shown ? "translateY(0) rotate(45deg)" : "translateY(-4px)",
                    }}
                />
                <span
                    style={{
                        position: "absolute",
                        width: 20,
                        height: 1.5,
                        borderRadius: 2,
                        background: text,
                        transition: reduced ? "none" : `transform 380ms ${EASE}`,
                        transform: shown ? "translateY(0) rotate(-45deg)" : "translateY(4px)",
                    }}
                />
            </button>

            {/*
                Rendered here, then moved to <body> by the effect above. On the
                Framer canvas it stays put, so positioning is approximate on
                canvas and exact when published.
            */}
            {overlay}
        </>
    )
}

addPropertyControls(MobileNav, {
    items: {
        type: ControlType.Array,
        title: "Items",
        control: {
            type: ControlType.Object,
            controls: {
                label: { type: ControlType.String, title: "Label", defaultValue: "Features" },
                link: { type: ControlType.Link, title: "Link" },
            },
        },
        defaultValue: [
            { label: "Features", link: "/#features-overview" },
            { label: "How It Works", link: "/#how-it-works" },
            { label: "Pricing", link: "/#pricing" },
            { label: "FAQ", link: "/#faq" },
            { label: "Marketplace", link: "/marketplace" },
        ],
    },
    ctaLabel: { type: ControlType.String, title: "CTA label", defaultValue: "Get my 40 companies" },
    ctaLink: {
        type: ControlType.Link,
        title: "CTA link",
    },
    widthPercent: {
        type: ControlType.Number,
        title: "Width",
        defaultValue: 75,
        min: 50,
        max: 100,
        step: 1,
        unit: "%",
        description: "Share of the screen the panel covers.",
    },
    maxWidth: {
        type: ControlType.Number,
        title: "Max width",
        defaultValue: 420,
        min: 240,
        max: 720,
        step: 10,
        unit: "px",
        description: "Stops the panel becoming a wall on a tablet.",
    },
    hideAbove: {
        type: ControlType.Number,
        title: "Hide above",
        defaultValue: 1200,
        min: 600,
        max: 1600,
        step: 10,
        unit: "px",
        description: "Width at which the hamburger disappears and the desktop nav takes over.",
    },
    eyebrow: { type: ControlType.String, title: "Eyebrow", defaultValue: "MENU" },
    footnote: {
        type: ControlType.String,
        title: "Footnote",
        defaultValue: "Four client slots, then I stop taking work.",
    },
    previewOpen: {
        type: ControlType.Boolean,
        title: "Preview open",
        defaultValue: false,
        description: "Canvas only. Ignored on the published site.",
    },
    surface: { type: ControlType.Color, title: "Surface", defaultValue: "rgb(17, 17, 17)" },
    border: { type: ControlType.Color, title: "Border", defaultValue: "rgb(26, 26, 26)" },
    text: { type: ControlType.Color, title: "Text", defaultValue: "rgb(240, 240, 240)" },
    muted: { type: ControlType.Color, title: "Muted", defaultValue: "rgb(136, 136, 136)" },
    accent: { type: ControlType.Color, title: "Accent", defaultValue: "rgb(0, 255, 136)" },
})
