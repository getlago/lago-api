# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::Stores::Utils::ClickhouseSqlHelpers do
  subject(:helper) { Class.new { include Events::Stores::Utils::ClickhouseSqlHelpers }.new }

  describe "#sanitize_clickhouse_sql" do
    it "doubles backslashes and quotes in string values" do
      expect(helper.sanitize_clickhouse_sql(["properties[?]", "a\\'b\\"])).to eq("properties['a\\\\''b\\\\']")
    end

    it "escapes string values of arrays and named binds" do
      expect(helper.sanitize_clickhouse_sql(["code IN (?)", ["a\\", "b"]])).to eq("code IN ('a\\\\','b')")
      expect(helper.sanitize_clickhouse_sql(["code = :code", {code: "a\\"}])).to eq("code = 'a\\\\'")
    end

    it "escapes symbol values" do
      expect(helper.sanitize_clickhouse_sql(["properties[?]", :"a\\"])).to eq("properties['a\\\\']")
    end

    it "quotes dates and numbers like ActiveRecord" do
      time = Time.zone.parse("2026-10-18 12:34:56.789")

      expect(helper.sanitize_clickhouse_sql(["timestamp >= ? AND value = ?", time, 3]))
        .to eq(ActiveRecord::Base.sanitize_sql_for_conditions(["timestamp >= ? AND value = ?", time, 3]))
    end
  end

  describe "#quote" do
    it "quotes with the ClickHouse adapter" do
      expect(helper.quote("a\\'b")).to eq("'a\\\\''b'")
    end
  end

  describe "#decimal_literal" do
    it "renders a fixed-point string" do
      expect(helper.decimal_literal(2500.0)).to eq("2500.0")
      expect(helper.decimal_literal("0.000000000000000001")).to eq("0.000000000000000001")
    end
  end
end
