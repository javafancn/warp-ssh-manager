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
}

impl Palette {
    pub fn new(dark: bool) -> Self {
        if dark {
            Self {
                app: 0x101722, titlebar: 0x18212E, sidebar: 0x1B2432,
                list: 0x131B27, inspector: 0x18212E, control: 0x263242,
                border: 0x303C4D, primary: 0xF1F5FC, secondary: 0xA1B0C4,
                tertiary: 0x728197, accent: 0x3079F5, accent_foreground: 0xFFFFFF,
                selected: 0x1A3D75, selected_border: 0x367AF1, chip: 0x303B4B,
                danger: 0xF08C8C, danger_surface: 0x542F38, success: 0x4FDA8A,
                prod_surface: 0x223F71, prod_foreground: 0x91BBFF,
                stage_surface: 0x3B275A, stage_foreground: 0xCDB0FE,
                dev_surface: 0x173E32, dev_foreground: 0x80DDAB,
            }
        } else {
            Self {
                app: 0xF7F9FC, titlebar: 0xF8FAFD, sidebar: 0xF0F3F8,
                list: 0xFFFFFF, inspector: 0xFFFFFF, control: 0xF3F5F9,
                border: 0xE0E6EF, primary: 0x192638, secondary: 0x57677D,
                tertiary: 0x8B98AB, accent: 0x246DF2, accent_foreground: 0xFFFFFF,
                selected: 0xE6EFFF, selected_border: 0x427EF3, chip: 0xEBEFF5,
                danger: 0xC53A49, danger_surface: 0xFCE7E8, success: 0x209E59,
                prod_surface: 0xE5EEFF, prod_foreground: 0x235ECB,
                stage_surface: 0xF0E5FF, stage_foreground: 0x8C4ACA,
                dev_surface: 0xE0F5E9, dev_foreground: 0x208451,
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
