import React, { useState } from "react";

interface Props {
  text: string;
}

export default function CopyButton({ text }: Props) {
  const [copied, setCopied] = useState(false);

  async function handleCopy() {
    await navigator.clipboard.writeText(text);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  return (
    <button
      className="btn btn-icon"
      onClick={handleCopy}
      title="Copy to clipboard"
      aria-label={copied ? "Copied!" : "Copy to clipboard"}
      style={{ flexShrink: 0, fontSize: "var(--font-size-sm)" }}
    >
      {copied ? "✓" : "⎘"}
    </button>
  );
}
