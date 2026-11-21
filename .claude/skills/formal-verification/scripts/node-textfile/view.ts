export const title = "Node Exporter textfile alert";

export const state = ({ streak }: { streak: number }) => {
  if (streak === 0) {
    return "Inactive";
  }
  return streak === 6 ? "Firing" : "Pending";
};

export const step = (
  action: string,
  from: { streak: number },
  to: { streak: number }
) => {
  if (action.includes("Ineligible")) {
    return "Exporter is unreachable or collector error clears";
  }
  if (action.includes("ReachableWithError")) {
    if (from.streak === 0) {
      return "Reachable exporter reports a collector error";
    }
    if (from.streak < 6 && to.streak === 6) {
      return "Error persists for five minutes";
    }
    return "Error continues";
  }
  throw new Error(`Unknown evaluation: ${action}`);
};
