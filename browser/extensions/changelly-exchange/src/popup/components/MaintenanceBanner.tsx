import React from "react";
import { useAppState } from "../state/AppStore";

export default function MaintenanceBanner() {
  const state = useAppState();
  if (!state.maintenanceMode) return null;

  return (
    <div className="banner banner-warning" role="status" aria-live="polite" style={{ borderRadius: 0, marginBottom: -8 }}>
      Changelly exchange is temporarily unavailable for maintenance. Please check back shortly.
    </div>
  );
}
