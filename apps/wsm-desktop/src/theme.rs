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
            }
        } else {
            Self {
                app: 0xEFF4FC, titlebar: 0xF8FBFF, sidebar: 0xEAF0FA,
                list: 0xF7FAFF, inspector: 0xFFFFFF, control: 0xEFF3F9,
                border: 0xD6E0EF, primary: 0x15243E, secondary: 0x5B6E8B,
                tertiary: 0x8598B4, accent: 0x1674F8, accent_foreground: 0xFFFFFF,
                selected: 0xE5F0FF, selected_border: 0x3280FF, chip: 0xE9F1FF,
                danger: 0xC53A49, danger_surface: 0xFCE7E8, success: 0x209E59,
                prod_surface: 0xE5EEFF, prod_foreground: 0x235ECB,
                stage_surface: 0xF0E5FF, stage_foreground: 0x8C4ACA,
                dev_surface: 0xE0F5E9, dev_foreground: 0x208451,
                warning_surface: 0xFFF0DD, warning_foreground: 0xA95715,
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
    }
    #[test]
    fn explicit_override_is_independent_of_system() {
        assert!(Appearance::Dark.dark(WindowAppearance::Light));
        assert!(!Appearance::Light.dark(WindowAppearance::Dark));
    }
}
