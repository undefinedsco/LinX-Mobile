export const LinxPalette = {
  accent: '#0d7568',
  accentPressed: '#0a6257',
  blue: '#1f5fae',
  warning: '#c43f32',
  warningPressed: '#9f3027',
  light: {
    background: '#eff6f3',
    backgroundAlt: '#f9f7ef',
    surface: '#ffffff',
    elevatedSurface: '#f5faf7',
    border: '#dbe7e1',
    text: '#111b18',
    secondaryText: '#64716c',
    tertiaryText: '#8a9691',
    input: '#ffffff',
    selected: '#dff1ec',
  },
  dark: {
    background: '#0b1114',
    backgroundAlt: '#10181b',
    surface: '#161f23',
    elevatedSurface: '#1d282c',
    border: '#2f3c40',
    text: '#eef7f4',
    secondaryText: '#a8b6b1',
    tertiaryText: '#768681',
    input: '#10181b',
    selected: '#12342f',
  },
} as const;

export function linxColors(isDark: boolean) {
  return isDark ? LinxPalette.dark : LinxPalette.light;
}
