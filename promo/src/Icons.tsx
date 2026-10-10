import React from "react";

type IconProps = { size?: number; color?: string; style?: React.CSSProperties };

const Svg: React.FC<IconProps & { children: React.ReactNode; viewBox?: string }> = ({
  size = 16,
  color = "currentColor",
  style,
  children,
  viewBox = "0 0 24 24",
}) => (
  <svg width={size} height={size} viewBox={viewBox} fill={color} style={{ display: "block", ...style }}>
    {children}
  </svg>
);

const strokeProps = (color: string, width = 2) => ({
  fill: "none",
  stroke: color,
  strokeWidth: width,
  strokeLinecap: "round" as const,
  strokeLinejoin: "round" as const,
});

export const Play: React.FC<IconProps> = (p) => (
  <Svg {...p}>
    <path d="M7 4.5v15c0 .8.9 1.3 1.6.9l12-7.5c.6-.4.6-1.4 0-1.8l-12-7.5C7.9 3.2 7 3.7 7 4.5z" />
  </Svg>
);

export const Pause: React.FC<IconProps> = (p) => (
  <Svg {...p}>
    <rect x="5.5" y="4" width="4.5" height="16" rx="1.2" />
    <rect x="14" y="4" width="4.5" height="16" rx="1.2" />
  </Svg>
);

export const Forward: React.FC<IconProps> = (p) => (
  <Svg {...p}>
    <path d="M2 6.2v11.6c0 .8.9 1.2 1.5.8l8.5-5.8c.6-.4.6-1.2 0-1.6L3.5 5.4C2.9 5 2 5.4 2 6.2zM12 6.2v11.6c0 .8.9 1.2 1.5.8l8.5-5.8c.6-.4.6-1.2 0-1.6l-8.5-5.8c-.6-.4-1.5 0-1.5.8z" />
  </Svg>
);

export const Backward: React.FC<IconProps> = (p) => <Forward {...p} style={{ ...p.style, transform: "scaleX(-1)" }} />;

export const Shuffle: React.FC<IconProps> = ({ color = "currentColor", ...p }) => (
  <Svg {...p}>
    <g {...strokeProps(color, 2.2)}>
      <path d="M3 7h3.5c4.5 0 6.5 10 11 10H21M3 17h3.5c1.8 0 3-1.6 4.2-3.6M13.3 9.6C14.5 8.1 15.8 7 17.5 7H21" />
      <path d="M18.5 4.5 21 7l-2.5 2.5M18.5 14.5 21 17l-2.5 2.5" />
    </g>
  </Svg>
);

export const Repeat: React.FC<IconProps> = ({ color = "currentColor", ...p }) => (
  <Svg {...p}>
    <g {...strokeProps(color, 2.2)}>
      <path d="M4 11V9.5A3.5 3.5 0 0 1 7.5 6H20M17 3l3 3-3 3M20 13v1.5a3.5 3.5 0 0 1-3.5 3.5H4M7 21l-3-3 3-3" />
    </g>
  </Svg>
);

export const Gear: React.FC<IconProps> = ({ color = "currentColor", ...p }) => (
  <Svg {...p}>
    <g {...strokeProps(color, 1.8)}>
      <circle cx="12" cy="12" r="3.2" />
      <path d="M12 2.5v2.6M12 18.9v2.6M21.5 12h-2.6M5.1 12H2.5M18.7 5.3l-1.8 1.8M7.1 16.9l-1.8 1.8M18.7 18.7l-1.8-1.8M7.1 7.1 5.3 5.3" />
      <circle cx="12" cy="12" r="6.6" />
    </g>
  </Svg>
);

export const ClipboardIcon: React.FC<IconProps> = ({ color = "currentColor", ...p }) => (
  <Svg {...p}>
    <g {...strokeProps(color, 1.9)}>
      <rect x="5" y="4.5" width="14" height="17" rx="2.5" />
      <rect x="9" y="2.5" width="6" height="4" rx="1.2" />
      <path d="M9 12h6M9 16h4" />
    </g>
  </Svg>
);

export const Video: React.FC<IconProps> = (p) => (
  <Svg {...p}>
    <rect x="2" y="6" width="13.5" height="12" rx="3" />
    <path d="M17 10.2 21.2 7.6c.4-.3.8 0 .8.4v8c0 .5-.4.7-.8.4L17 13.8z" />
  </Svg>
);

export const Calendar: React.FC<IconProps> = ({ color = "currentColor", ...p }) => (
  <Svg {...p}>
    <g {...strokeProps(color, 2)}>
      <rect x="3.5" y="5" width="17" height="15.5" rx="3" />
      <path d="M3.5 10h17M8 3v4M16 3v4" />
    </g>
  </Svg>
);

export const Checklist: React.FC<IconProps> = ({ color = "currentColor", ...p }) => (
  <Svg {...p}>
    <g {...strokeProps(color, 2.2)}>
      <path d="m3 6 2 2 3.5-3.5M3 15l2 2 3.5-3.5M12 7h9M12 16h9" />
    </g>
  </Svg>
);

export const Flame: React.FC<IconProps & { filled?: boolean }> = ({ color = "currentColor", filled = true, ...p }) => (
  <Svg {...p}>
    <path
      d="M12 22c-4.4 0-7.5-3-7.5-7 0-3.4 2.2-5.6 3.8-7.6.4-.5 1.2-.2 1.2.4 0 1.3.7 2.5 1.8 2.9C11 7.6 12 4.3 14.2 2.3c.4-.4 1-.1 1.1.4.3 2.6 1.6 4.2 2.8 5.8 1.2 1.6 1.9 3.5 1.9 5.9C20 18.8 16.7 22 12 22z"
      fill={filled ? color : "none"}
      stroke={filled ? "none" : color}
      strokeWidth={2}
    />
  </Svg>
);

export const Battery: React.FC<IconProps> = ({ color = "currentColor", ...p }) => (
  <Svg {...p}>
    <rect x="1.5" y="7" width="18" height="10" rx="2.6" fill="none" stroke={color} strokeWidth="1.6" />
    <rect x="3.5" y="9" width="11" height="6" rx="1.2" fill={color} />
    <path d="M21 10.3v3.4" stroke={color} strokeWidth="1.8" strokeLinecap="round" />
  </Svg>
);

export const Drive: React.FC<IconProps> = ({ color = "currentColor", ...p }) => (
  <Svg {...p}>
    <g {...strokeProps(color, 2)}>
      <rect x="3" y="12" width="18" height="7.5" rx="2" />
      <path d="M5 12 7.5 5h9L19 12" />
      <circle cx="16.5" cy="15.8" r=".6" fill={color} />
    </g>
  </Svg>
);

export const Network: React.FC<IconProps> = ({ color = "currentColor", ...p }) => (
  <Svg {...p}>
    <g {...strokeProps(color, 2)}>
      <circle cx="12" cy="12" r="9" />
      <path d="M3 12h18M12 3c2.5 2.6 3.8 5.6 3.8 9s-1.3 6.4-3.8 9c-2.5-2.6-3.8-5.6-3.8-9S9.5 5.6 12 3z" />
    </g>
  </Svg>
);

export const Reset: React.FC<IconProps> = ({ color = "currentColor", ...p }) => (
  <Svg {...p}>
    <g {...strokeProps(color, 2.6)}>
      <path d="M4.5 12a7.5 7.5 0 1 0 2.2-5.3L4.5 9" />
      <path d="M4.5 4v5h5" />
    </g>
  </Svg>
);

export const Trash: React.FC<IconProps> = ({ color = "currentColor", ...p }) => (
  <Svg {...p}>
    <g {...strokeProps(color, 2)}>
      <path d="M4 6.5h16M9.5 6.5V4.5h5v2M6 6.5l1 13.5h10l1-13.5" />
    </g>
  </Svg>
);

export const Checkmark: React.FC<IconProps> = ({ color = "currentColor", ...p }) => (
  <Svg {...p}>
    <path d="m5 12.5 4.5 4.5L19 7.5" {...strokeProps(color, 3.2)} />
  </Svg>
);

export const Pin: React.FC<IconProps> = (p) => (
  <Svg {...p}>
    <path d="M8 3h8l-1.3 6.2L18 12.5v1.5h-5.2V21L12 22l-.8-1v-7H6v-1.5l3.3-3.3z" />
  </Svg>
);

export const Apple: React.FC<IconProps> = (p) => (
  <Svg {...p} viewBox="0 0 814 1000">
    <path d="M788 341c-6 4-108 62-108 190 0 149 131 202 135 203-1 3-21 72-69 142-43 62-88 124-156 124s-86-40-165-40c-77 0-104 41-166 41s-106-57-156-127C45 792 0 667 0 549c0-190 124-291 246-291 65 0 119 43 160 43 39 0 100-45 174-45 28 0 129 3 196 99zM554 160c31-36 52-87 52-138 0-7-1-14-2-20-50 2-109 33-145 75-28 32-54 83-54 135 0 8 1 15 2 18 3 1 9 1 14 1 45 0 101-30 133-71z" />
  </Svg>
);

export const Wifi: React.FC<IconProps> = ({ color = "currentColor", ...p }) => (
  <Svg {...p}>
    <g {...strokeProps(color, 2.4)}>
      <path d="M2.5 9a14 14 0 0 1 19 0M5.8 12.5a9.2 9.2 0 0 1 12.4 0M9.1 16a4.6 4.6 0 0 1 5.8 0" />
    </g>
    <circle cx="12" cy="19.3" r="1.6" fill={color} />
  </Svg>
);

export const Search: React.FC<IconProps> = ({ color = "currentColor", ...p }) => (
  <Svg {...p}>
    <g {...strokeProps(color, 2.4)}>
      <circle cx="10.5" cy="10.5" r="6.5" />
      <path d="m15.5 15.5 5 5" />
    </g>
  </Svg>
);

export const ControlCenter: React.FC<IconProps> = ({ color = "currentColor", ...p }) => (
  <Svg {...p}>
    <g {...strokeProps(color, 2)}>
      <rect x="2.5" y="4.5" width="19" height="6" rx="3" />
      <rect x="2.5" y="13.5" width="19" height="6" rx="3" />
    </g>
    <circle cx="17.5" cy="7.5" r="1.8" fill={color} />
    <circle cx="6.5" cy="16.5" r="1.8" fill={color} />
  </Svg>
);
