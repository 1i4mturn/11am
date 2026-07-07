/** Dual wash + grain stack — matches home dashboard & brand guidelines */

export function SuiteAtmosphere() {
  return (
    <>
      <div className="am-wash am-wash-dark" aria-hidden="true" />
      <div className="am-wash am-wash-light" aria-hidden="true" />
      <svg className="am-grain-svg am-grain-coarse" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
        <filter id="am-grain-coarse">
          <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" stitchTiles="stitch" />
          <feColorMatrix type="saturate" values="0" />
        </filter>
        <rect width="100%" height="100%" filter="url(#am-grain-coarse)" />
      </svg>
      <svg className="am-grain-svg am-grain-fine" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
        <filter id="am-grain-fine">
          <feTurbulence type="fractalNoise" baseFrequency="0.35" numOctaves="2" stitchTiles="stitch" />
          <feColorMatrix type="saturate" values="0" />
        </filter>
        <rect width="100%" height="100%" filter="url(#am-grain-fine)" />
      </svg>
    </>
  );
}
