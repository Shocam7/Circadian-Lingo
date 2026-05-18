---
name: Circadian Lingo
colors:
  surface: '#faf8ff'
  surface-dim: '#d2d9f4'
  surface-bright: '#faf8ff'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f2f3ff'
  surface-container: '#eaedff'
  surface-container-high: '#e2e7ff'
  surface-container-highest: '#dae2fd'
  on-surface: '#131b2e'
  on-surface-variant: '#43474b'
  inverse-surface: '#283044'
  inverse-on-surface: '#eef0ff'
  outline: '#73787b'
  outline-variant: '#c3c7cb'
  surface-tint: '#50616b'
  primary: '#50616b'
  on-primary: '#ffffff'
  primary-container: '#e0f2fe'
  on-primary-container: '#5e6f79'
  inverse-primary: '#b7c9d5'
  secondary: '#635b6e'
  on-secondary: '#ffffff'
  secondary-container: '#e9def5'
  on-secondary-container: '#696174'
  tertiary: '#605f53'
  on-tertiary: '#ffffff'
  tertiary-container: '#f4f0e0'
  on-tertiary-container: '#6f6d60'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#d3e5f1'
  primary-fixed-dim: '#b7c9d5'
  on-primary-fixed: '#0c1e26'
  on-primary-fixed-variant: '#384953'
  secondary-fixed: '#e9def5'
  secondary-fixed-dim: '#cdc2d9'
  on-secondary-fixed: '#1e1929'
  on-secondary-fixed-variant: '#4a4456'
  tertiary-fixed: '#e6e3d3'
  tertiary-fixed-dim: '#cac7b8'
  on-tertiary-fixed: '#1c1c13'
  on-tertiary-fixed-variant: '#48473c'
  background: '#faf8ff'
  on-background: '#131b2e'
  surface-variant: '#dae2fd'
typography:
  headline-xl:
    fontFamily: Plus Jakarta Sans
    fontSize: 40px
    fontWeight: '800'
    lineHeight: '1.4'
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 32px
    fontWeight: '700'
    lineHeight: '1.5'
    letterSpacing: -0.01em
  headline-lg-mobile:
    fontFamily: Plus Jakarta Sans
    fontSize: 28px
    fontWeight: '700'
    lineHeight: '1.5'
  body-lg:
    fontFamily: Lexend
    fontSize: 18px
    fontWeight: '400'
    lineHeight: '1.7'
  body-md:
    fontFamily: Lexend
    fontSize: 16px
    fontWeight: '400'
    lineHeight: '1.6'
  label-md:
    fontFamily: Lexend
    fontSize: 14px
    fontWeight: '500'
    lineHeight: '1.6'
    letterSpacing: 0.02em
rounded:
  sm: 0.5rem
  DEFAULT: 1rem
  md: 1.5rem
  lg: 2rem
  xl: 3rem
  full: 9999px
spacing:
  unit: 8px
  container-padding: 24px
  gutter: 16px
  section-gap: 48px
---

## Brand & Style

This design system is built on the concept of "The Gentle Awakening." It aims to transform language learning from a chore into a restorative daily ritual. The aesthetic avoids the high-pressure, gamified anxiety of competitors, opting instead for an atmosphere that feels like a quiet morning—clear, hopeful, and full of potential.

The style leverages **Minimalism** for clarity and **Glassmorphism** for depth. It uses wide open spaces to reduce cognitive load and semi-transparent layers to suggest a sky-like lightness. Every interaction should feel soft and encouraging, never clinical or punishing. The target audience is learners seeking a mindful, inclusive, and empowering educational environment.

## Colors

The palette is derived from the transition of pre-dawn to early morning. 
- **Primary (Sky):** #E0F2FE is used for main surfaces and "airy" focal points.
- **Secondary (Lavender):** #F3E8FF acts as a soft highlight for interactive zones and progress indicators.
- **Tertiary (Cream):** #FFFBEB provides a warm, paper-like grounding for reading areas.
- **Neutral:** A deep navy-charcoal (#0F172A) is used for typography to ensure AAA accessibility against the pale backgrounds.

Avoid solid blacks or harsh grays. When transparency is required, use background blurs (12px-20px) with 60-80% opacity to maintain the "soft dawn" atmosphere.

## Typography

The typography strategy prioritizes warmth and ultra-readability. 
- **Headlines:** **Plus Jakarta Sans** provides a modern, rounded geometric look with "character" that feels optimistic.
- **Body & Labels:** **Lexend** was specifically designed to reduce visual stress and improve reading speed, making it the perfect choice for a learning app.

A generous line-height of 1.6 to 1.7 is strictly enforced across all body text to ensure the UI feels "airy" and uncrowded. Text should never feel cramped; white space is as important as the characters themselves.

## Layout & Spacing

This design system utilizes a **Fluid Grid** with significant "safe zones." 
- **Mobile:** A 4-column grid with 24px side margins to prevent elements from feeling crowded against the screen edge.
- **Desktop:** A centered 12-column max-width container (1120px) to maintain focus.

The spacing rhythm is built on an 8px base unit, but emphasizes large "Section Gaps" (48px+) to separate different learning modules. Content should never feel "packed." If in doubt, increase the padding. Organic, blob-like SVG elements should float in the margins, occasionally breaking the grid to create a sense of movement and life.

## Elevation & Depth

Depth in this design system is atmospheric rather than structural. We avoid heavy, dark shadows.
- **Ambient Shadows:** Use large-blur (30px-50px) shadows with very low opacity (5-8%). Shadows should be tinted with the secondary lavender color `#F3E8FF` rather than neutral gray to maintain the color narrative.
- **Tonal Layering:** Depth is primarily achieved by stacking light colors (e.g., a Lavender card on a Sky Blue background).
- **Glassmorphism:** Use for overlays and navigation bars. A `backdrop-filter: blur(16px)` combined with a subtle 1px white border at 20% opacity creates a "frosted morning glass" effect.

## Shapes

The shape language is defined by "The Soft Edge." 
- **Containers:** All primary cards and modals must use a minimum border-radius of **28px**. 
- **Interactive Elements:** Buttons and input fields should utilize a **Pill-shape** (fully rounded) to evoke a friendly, non-threatening tactile feel.
- **Decorative:** Incorporate "Blobs"—organic, non-symmetrical SVG shapes—behind text or in corners. These should have no hard angles and should use the gradient transitions between the primary and secondary colors.

## Components

### Buttons
Primary buttons use a soft gradient from Lavender to Sky Blue. They should have a "squishy" feel, achieved through a subtle scale-down (0.98) on tap. Typography inside buttons is bold Lexend.

### Cards
Cards are the primary vehicle for learning content. They should feature the 28px border radius, a subtle 1px soft-white border, and the ambient lavender-tinted shadow. No harsh borders.

### Progress Indicators
Avoid thin, clinical lines. Use thick, pill-shaped tracks with rounded caps. The "filled" portion of the progress bar should use a gentle gradient to signify growth.

### Input Fields
Inputs are pill-shaped with a warm cream (#FFFBEB) background. The focus state should not be a harsh outline, but a soft "glow" using the primary sky blue color.

### Lesson Chips
Small, rounded pills used for selecting words or categories. These should have a slight "bounce" animation when selected, reinforcing the encouraging vibe of the design system.