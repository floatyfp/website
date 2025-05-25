// Utility functions and constants for blog cards
export const badgeColors = {
  "changelog": "bg-[#9E6C00] text-yellow-100",
  "blog": "bg-[#64009E] text-fuchsia-100"
};

export function formatDate(dateString) {
  const date = new Date(dateString);
  if (isNaN(date)) return '';
  const day = date.getDate();
  const month = date.toLocaleString(undefined, { month: 'long' });
  const year = date.getFullYear().toString().slice(-2);
  return `${day} ${month} ${year}`;
}
