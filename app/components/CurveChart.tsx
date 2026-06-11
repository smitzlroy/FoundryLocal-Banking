"use client";

import {
  Line,
  LineChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
  Legend,
} from "recharts";
import type { TenorPoint } from "@/lib/types";

export function CurveChart({ curve }: { curve: TenorPoint[] }) {
  return (
    <div className="chart-wrap">
      <ResponsiveContainer width="100%" height="100%">
        <LineChart data={curve} margin={{ top: 10, right: 20, left: 0, bottom: 0 }}>
          <CartesianGrid stroke="#26314f" strokeDasharray="3 3" />
          <XAxis dataKey="label" stroke="#93a0bd" tick={{ fontSize: 12 }} />
          <YAxis
            stroke="#93a0bd"
            tick={{ fontSize: 12 }}
            domain={["auto", "auto"]}
            tickFormatter={(v) => `${v}%`}
          />
          <Tooltip
            contentStyle={{
              background: "#1b2440",
              border: "1px solid #26314f",
              borderRadius: 10,
              color: "#e8ecf6",
            }}
            labelFormatter={(label, payload) =>
              (payload?.[0]?.payload as { product?: string })?.product ?? String(label)
            }
            formatter={(v, name) => [`${Number(v).toFixed(2)}%`, name]}
          />
          <Legend wrapperStyle={{ fontSize: 12 }} />
          <Line
            type="monotone"
            dataKey="base"
            name="Rates today"
            stroke="#5b8cff"
            strokeWidth={2}
            dot={false}
          />
          <Line
            type="monotone"
            dataKey="forecast"
            name="Forecast"
            stroke="#38e0c4"
            strokeWidth={2.5}
            dot={{ r: 3 }}
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}
