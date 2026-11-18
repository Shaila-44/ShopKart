import { AlertTriangle, CheckCircle2, Clock, Loader2 } from "lucide-react";
import type { DeliveryStatus } from "../../api/automation";

const STYLES: Record<DeliveryStatus, { label: string; className: string; icon: typeof Clock }> = {
    sent: { label: "Sent", className: "bg-emerald-50 text-emerald-700 border-emerald-200", icon: CheckCircle2 },
    failed: { label: "Failed", className: "bg-red-50 text-red-700 border-red-200", icon: AlertTriangle },
    pending: { label: "Pending", className: "bg-amber-50 text-amber-700 border-amber-200", icon: Clock },
    sending: { label: "Sending", className: "bg-blue-50 text-blue-700 border-blue-200", icon: Loader2 },
};

export default function DeliveryStatusBadge({ status }: { status: DeliveryStatus }) {
    const style = STYLES[status] ?? STYLES.pending;
    const Icon = style.icon;
    return (
        <span className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg border text-xs font-bold ${style.className}`}>
            <Icon className={`w-3.5 h-3.5 ${status === "sending" ? "animate-spin" : ""}`} />
            {style.label}
        </span>
    );
}
