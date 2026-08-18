function normalize(key: string): string {
  return key.length === 1 ? key.toLowerCase() : key;
}

export class InputManager {
  private held = new Set<string>();
  private pressedThisFrame = new Set<string>();
  private justPressed = new Set<string>();

  constructor() {
    window.addEventListener("keydown", (e) => {
      const key = normalize(e.key);
      if (!this.held.has(key)) {
        this.pressedThisFrame.add(key);
      }
      this.held.add(key);
      if (
        ["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", " ", "Enter"].includes(
          e.key,
        )
      ) {
        e.preventDefault();
      }
    });
    window.addEventListener("keyup", (e) => {
      this.held.delete(normalize(e.key));
    });
  }

  isHeld(key: string): boolean {
    return this.held.has(key);
  }

  /** True for exactly one update() cycle after the key was pressed. */
  wasPressed(key: string): boolean {
    return this.justPressed.has(key);
  }

  /** Call once per frame after reading input to advance edge-detection state. */
  endFrame(): void {
    this.justPressed = new Set(this.pressedThisFrame);
    this.pressedThisFrame.clear();
  }
}
