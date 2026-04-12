import React from "react";

interface Props extends React.HTMLAttributes<HTMLDivElement> {
  width?: number | string;
  height?: number | string;
  circle?: boolean;
}

export default function Skeleton({ width = "100%", height = 16, circle, style, ...rest }: Props) {
  return (
    <div
      className="skeleton"
      style={{
        width,
        height,
        borderRadius: circle ? "50%" : "var(--radius-sm)",
        flexShrink: 0,
        ...style,
      }}
      aria-hidden="true"
      {...rest}
    />
  );
}
