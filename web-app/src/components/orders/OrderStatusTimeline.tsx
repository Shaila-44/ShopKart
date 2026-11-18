import { CheckCircle2, Clock, PackageCheck, Truck, XCircle } from "lucide-react";
import type { OrderStatusEvent } from "../../api/order";

const STEPS = [
    { status: "pending", label: "Order placed", icon: Clock },
    { status: "confirmed", label: "Confirmed", icon: CheckCircle2 },
    { status: "shipped", label: "Shipped", icon: Truck },
    { status: "delivered", label: "Delivered", icon: PackageCheck },
] as const;

interface Props {
    status: string;
    events?: OrderStatusEvent[];
    createdAt?: string;
    compact?: boolean;
}

const formatTime = (iso?: string) =>
    iso
        ? new Date(iso).toLocaleString("en-IN", {
              day: "numeric",
              month: "short",
              hour: "2-digit",
              minute: "2-digit",
          })
        : null;

/**
 * Order progress built from the backend's order_status_events (the source of truth),
 * so it always reflects the latest admin updates after a refresh.
 */
export default function OrderStatusTimeline({ status, events = [], createdAt, compact = false }: Props) {
    const timeFor = (s: string) => {
        const event = [...events].reverse().find((e) => e.to_status === s);
        if (event) return event.created_at;
        return s === "pending" ? createdAt : undefined;
    };

    const isCancelled = status === "cancelled";
    const cancelledEvent = events.find((e) => e.to_status === "cancelled");
    // For cancelled orders, show progress up to the status they were cancelled from.
    const effectiveStatus = isCancelled ? cancelledEvent?.from_status ?? "pending" : status;
    const reachedIndex = Math.max(0, STEPS.findIndex((s) => s.status === effectiveStatus));

    const steps = STEPS.map((step, index) => ({
        ...step,
        reached: index <= reachedIndex,
        current: !isCancelled && index === reachedIndex,
        time: index <= reachedIndex ? formatTime(timeFor(step.status)) : null,
    }));

    return (
        <div className={compact ? "" : "rounded-2xl border border-neutral-100 bg-neutral-50/60 p-4 sm:p-5"}>
            <ol className="relative flex flex-col sm:flex-row sm:items-start gap-4 sm:gap-0">
                {steps.map((step, index) => {
                    const Icon = step.icon;
                    const isLast = index === steps.length - 1;
                    return (
                        <li key={step.status} className="relative flex sm:flex-col sm:items-center sm:flex-1 gap-3 sm:gap-2 sm:text-center">
                            {!isLast && (
                                <span
                                    aria-hidden
                                    className={`hidden sm:block absolute top-4 left-1/2 w-full h-0.5 ${
                                        steps[index + 1].reached && !isCancelled ? "bg-primary-500" : "bg-neutral-200"
                                    }`}
                                />
                            )}
                            <span
                                className={`relative z-10 flex h-8 w-8 shrink-0 items-center justify-center rounded-full border-2 transition-colors ${
                                    step.reached
                                        ? "border-primary-600 bg-primary-600 text-white"
                                        : "border-neutral-200 bg-white text-neutral-300"
                                } ${step.current ? "ring-4 ring-primary-100" : ""}`}
                            >
                                <Icon className="h-4 w-4" />
                            </span>
                            <div className="min-w-0">
                                <p className={`text-sm font-bold ${step.reached ? "text-neutral-900" : "text-neutral-400"}`}>
                                    {step.label}
                                </p>
                                <p className="text-xs text-neutral-500 mt-0.5 min-h-[1rem]">
                                    {step.time ?? (step.reached ? "" : "Pending")}
                                </p>
                            </div>
                        </li>
                    );
                })}
            </ol>

            {isCancelled && (
                <div className="mt-4 flex items-center gap-2 rounded-xl border border-red-100 bg-red-50 px-3 py-2 text-sm text-red-700">
                    <XCircle className="h-4 w-4 shrink-0" />
                    <span className="font-semibold">Cancelled</span>
                    {cancelledEvent && <span className="text-red-600/80">· {formatTime(cancelledEvent.created_at)}</span>}
                </div>
            )}
        </div>
    );
}
