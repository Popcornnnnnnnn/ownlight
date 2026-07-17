import { type ReactNode, useEffect, useState } from "react";
import { Image as ImageIcon, Mic, Video, X } from "lucide-react";

import type { AdminMedia } from "./adminApi";

export function ImageLightbox({
  media,
  onClose,
  token,
}: {
  media: AdminMedia;
  onClose: () => void;
  token: string;
}) {
  return (
    <div className="lightbox" onClick={onClose} role="presentation">
      <button className="lightbox-close" onClick={onClose} type="button">
        <X size={20} />
      </button>
      <AuthenticatedImage
        alt="Full size post media"
        className="lightbox-image"
        src={media.compressedUrl ?? media.originalUrl}
        token={token}
      />
    </div>
  );
}

export function AuthenticatedImage({
  alt,
  className,
  src,
  token,
}: {
  alt: string;
  className: string;
  src: string | null;
  token: string;
}) {
  const [objectURL, setObjectURL] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    let nextURL: string | null = null;

    async function load() {
      if (!src) {
        setObjectURL(null);
        return;
      }

      const response = await fetch(src, {
        headers: {
          Authorization: `Bearer ${token}`,
        },
      });

      if (!response.ok) {
        throw new Error("Image unavailable");
      }

      const blob = await response.blob();
      nextURL = URL.createObjectURL(blob);
      if (!cancelled) {
        setObjectURL(nextURL);
      }
    }

    void load().catch(() => {
      if (!cancelled) {
        setObjectURL(null);
      }
    });

    return () => {
      cancelled = true;
      if (nextURL) {
        URL.revokeObjectURL(nextURL);
      }
    };
  }, [src, token]);

  if (!objectURL) {
    return (
      <div className={`${className} image-placeholder`}>
        <ImageIcon size={22} />
      </div>
    );
  }

  return <img alt={alt} className={className} src={objectURL} />;
}

export function Metric({
  detail,
  icon,
  label,
  value,
}: {
  detail: string;
  icon: ReactNode;
  label: string;
  value: string;
}) {
  return (
    <article className="metric">
      <div className="metric-icon">{icon}</div>
      <div>
        <span>{label}</span>
        <strong>{value}</strong>
        <small>{detail}</small>
      </div>
    </article>
  );
}

export function MetricLite({
  label,
  tone,
  value,
}: {
  label: string;
  tone: "good" | "warn" | "danger" | "neutral";
  value: string;
}) {
  return (
    <article className={`metric-lite ${tone}`}>
      <span>{label}</span>
      <strong>{value}</strong>
    </article>
  );
}

export function mediaIcon(kind: string) {
  if (kind === "video") {
    return <Video size={18} />;
  }

  if (kind === "audio") {
    return <Mic size={18} />;
  }

  return <ImageIcon size={18} />;
}
