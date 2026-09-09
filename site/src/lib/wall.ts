// The wall behind every page, from Shared/UI/Theme.swift: a warm dark ground, one ember glow
// that laps the room in a hundred seconds, a faint amber glow top right, and a light grain.
// Only the ember moves, and it moves on the compositor: one transform a frame, no repaint.

export function startWall(wall: HTMLElement) {
  const ember = wall.querySelector<HTMLElement>('.wall-ember');
  if (!ember) return;
  if (matchMedia('(prefers-reduced-motion: reduce)').matches) return;

  let W = wall.clientWidth, H = wall.clientHeight;
  addEventListener('resize', () => { W = wall.clientWidth; H = wall.clientHeight; });

  // Start forty seconds in, so the first frame puts the ember low on the left where it rests.
  const t0 = performance.now() / 1000 - 40;
  let last = 0;

  /// Where the ember sits, as a fraction of the wall. The orbit is polar, so the ember always
  /// clears the middle of the screen, where the content is.
  const center = (phase: number) => {
    const angle = (phase / 103) * 2 * Math.PI + 0.18 * Math.sin((phase / 32) * 2 * Math.PI);
    const reach = 0.86 + 0.2 * Math.sin((phase / 41) * 2 * Math.PI);
    return { x: 0.5 + 0.7 * reach * Math.cos(angle), y: 0.5 + 0.56 * reach * Math.sin(angle) };
  };

  const frame = (now: number) => {
    requestAnimationFrame(frame);
    if (now - last < 33) return;
    last = now;
    const { x, y } = center(now / 1000 - t0);
    // The glow element is 2 × 0.58 W wide and 2 × 0.35 H tall; move its middle to the point.
    ember.style.transform = `translate3d(${(x - 0.58) * W}px, ${(y - 0.35) * H}px, 0)`;
  };
  requestAnimationFrame(frame);
}
