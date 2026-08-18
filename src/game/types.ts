export interface KeyBindings {
  left: string;
  right: string;
}

export interface PlayerConfig {
  id: number;
  name: string;
  color: string;
  darkColor: string;
  keys: KeyBindings;
}

export interface PlayerResult {
  name: string;
  distance: number;
  survivedSeconds: number;
  alive: boolean;
}
