//! Product palette matching the approved dark/light macOS concept.
//! One appearance preference is shared by the main manager and quick connect UI.
use gpui::{WindowAppearance};
use gpui_component::theme::ThemeMode;
use std::{fs, path::Path};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Appearance {
    System,
    Dark,
    Light,
}

impl Appearance {
    pub fn read(data_dir: &Path) -> Self {
        match fs::read_to_string(data_dir.join("appearance.txt"))
            .unwrap_or_default().trim() {
            "dark" => Self::Dark,
            "light" => Self::Light,
            _ => Self::System,
        }
    }

    pub fn save(self, data_dir: &Path) -> std::io::Result<()> {
        fs::create_dir_all(data_dir)?;
        fs::write(data_dir.join("appearance.txt"), match self {
            Self::System => "system\n", Self::Dark => "dark\n", Self::Light => "light\n",
        })
    }

    pub fn dark(self, appearance: WindowAppearance) -> bool {
        match self {
            Self::Dark => true,
            Self::Light => false,
            Self::System => matches!(appearance, WindowAppearance::Dark | WindowAppearance::VibrantDark),
        }
    }

    pub fn mode(self, appearance: WindowAppearance) -> ThemeMode {
        if self.dark(appearance) { ThemeMode::Dark } else { ThemeMode::Light }
    }
}

#[derive(Debug, Clone, Copy)]
pub struct Palette {
    pub app: u32,
    pub titlebar: u32,
    pub sidebar: u32,
    pub list: u32,
    pub inspector: u32,
    pub control: u32,
    pub border: u32,
    pub primary: u32,
    pub secondary: u32,
    pub tertiary: u32,
    pub accent: u32,
    pub accent_foreground: u32,
    pub selected: u32,
    pub selected_border: u32,
    pub chip: u32,
    pub danger: u32,
    pub danger_surface: u32,
    pub success: u32,
    pub prod_surface: u32,
    pub prod_foreground: u32,
    pub stage_surface: u32,
    pub stage_foreground: u32,
    pub dev_surface: u32,
    pub dev_foreground: u32,
    pub warning_surface: u32,
    pub warning_foreground: u32,
    pub sidebar_end: u32,
    pub titlebar_end: u32,
    pub card_end: u32,
    pub selected_end: u32,
    pub card_selected: u32,
    pub card_selected_end: u32,
    pub card_selected_muted: u32,
    pub input_surface: u32,
    pub input_surface_end: u32,
    // Eight-digit RGBA colors for actual translucent panes over the gradient canvas.
    pub canvas_start: u32,
    pub canvas_end: u32,
    pub glass_sidebar: u32,
    pub glass_toolbar: u32,
    pub glass_list: u32,
    pub glass_inspector: u32,
    pub glass_card: u32,
    pub glass_selected: u32,
    pub glass_control: u32,
    pub glass_input: u32,
    pub glass_border: u32,
}

impl Palette {
    pub fn new(dark: bool) -> Self {
        if dark {
            Self {
                app: 0x0D1421, titlebar: 0x162239, sidebar: 0x1A263B,
                list: 0x111B2E, inspector: 0x17243A, control: 0x26344B,
                border: 0x324158, primary: 0xF4F7FF, secondary: 0xA8B8D3,
                tertiary: 0x879AB5, accent: 0x1979FA, accent_foreground: 0xFFFFFF,
                selected: 0x153D84, selected_border: 0x3191FF, chip: 0x253852,
                danger: 0xFF9BA5, danger_surface: 0x4A2B35, success: 0x4BD899,
                prod_surface: 0x223F71, prod_foreground: 0x91BBFF,
                stage_surface: 0x3B275A, stage_foreground: 0xCDB0FE,
                dev_surface: 0x173E32, dev_foreground: 0x80DDAB,
                warning_surface: 0x51371E, warning_foreground: 0xFFC385,
                sidebar_end: 0x20283A, titlebar_end: 0x192A42,
                card_end: 0x192A41, selected_end: 0x234B83,
                card_selected: 0x153767, card_selected_end: 0x28518A,
                card_selected_muted: 0xC1D4F0,
                input_surface: 0x202E45, input_surface_end: 0x273650,
                canvas_start: 0x0B1628, canvas_end: 0x242039,
                glass_sidebar: 0x19253BDC, glass_toolbar: 0x14243BC8,
                glass_list: 0x15243ABD, glass_inspector: 0x17243AD9,
                glass_card: 0x2A3857D6, glass_selected: 0x224F86D9,
                glass_control: 0x34425BAD, glass_input: 0x273750BB,
                glass_border: 0xA9C4ED29,
            }
        } else {
            Self {
                app: 0xF3F6FB, titlebar: 0xEFF4FB, sidebar: 0xE5EBF5,
                list: 0xF0F4FA, inspector: 0xF8FAFD, control: 0xF1F5FB,
                border: 0xD9E2EE, primary: 0x182840, secondary: 0x60718A,
                tertiary: 0x8598B4, accent: 0x1674F8, accent_foreground: 0xFFFFFF,
                selected: 0xD9E8FF, selected_border: 0x247CFF, chip: 0xE9F0FA,
                danger: 0xC53A49, danger_surface: 0xFCE7E8, success: 0x209E59,
                prod_surface: 0xE5EEFF, prod_foreground: 0x235ECB,
                stage_surface: 0xF0E5FF, stage_foreground: 0x8C4ACA,
                dev_surface: 0xE0F5E9, dev_foreground: 0x208451,
                warning_surface: 0xFFF0DD, warning_foreground: 0xA95715,
                sidebar_end: 0xEDE4EF, titlebar_end: 0xF7F9FD,
                card_end: 0xFBFCFF, selected_end: 0xEDF5FF,
                card_selected: 0xDFEDFF, card_selected_end: 0xF3F8FF,
                card_selected_muted: 0x58718F,
                input_surface: 0xFBFCFE, input_surface_end: 0xFFFFFF,
                canvas_start: 0xDCEAF8, canvas_end: 0xEEE2F0,
                glass_sidebar: 0xF7FAFFD1, glass_toolbar: 0xFFFFFFBF,
                glass_list: 0xF8FBFFB3, glass_inspector: 0xFFFFFFD9,
                glass_card: 0xFFFFFFE0, glass_selected: 0xE0ECFFD9,
                glass_control: 0xFFFFFFA8, glass_input: 0xFFFFFFC4,
                glass_border: 0x7189AF39,
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn both_themes_have_contrasting_surfaces() {
        let dark=Palette::new(true);
        let light=Palette::new(false);
        assert_ne!(dark.app,light.app);
        assert_ne!(dark.selected,light.selected);
        assert_ne!(dark.glass_sidebar, light.glass_sidebar);
        assert_eq!(light.glass_card & 0xff, 0xE0);
    }
    #[test]
    fn explicit_override_is_independent_of_system() {
        assert!(Appearance::Dark.dark(WindowAppearance::Light));
        assert!(!Appearance::Light.dark(WindowAppearance::Dark));
    }
}
