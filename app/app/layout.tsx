import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Sovereign Rate Forecast — Edge Inference",
  description:
    "Interest-rate forecasting running entirely at the edge on Foundry Local on Azure Local.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
