# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::ChargeService::Options do
  describe ".default" do
    it "returns default options" do
      expect(described_class.default).to have_attributes(
        context: nil,
        apply_taxes: false,
        calculate_projected_usage: false,
        with_zero_units_filters: true,
        usage_filters: UsageFilters::NONE,
        skip_adjusted_fees: false
      )
    end
  end

  describe "validations" do
    it "validates context" do
      expect { described_class.new(context: :current_usage) }.not_to raise_error
      expect { described_class.new(context: :refresh) }.not_to raise_error
      expect { described_class.new(context: :draft) }.not_to raise_error
      expect { described_class.new(context: :unknown) }
        .to raise_error(ArgumentError, "context 'unknown' must be one of: current_usage, invoice_preview, recurring, finalize, refresh, draft")
    end

    it "validates usage filters" do
      expect { described_class.new(usage_filters: UsageFilters.new) }.not_to raise_error
      expect { described_class.new(usage_filters: nil) }
        .to raise_error(ArgumentError, "usage_filters must be a UsageFilters")
    end

    it "validates booleans" do
      expect { described_class.new(apply_taxes: nil) }
        .to raise_error(ArgumentError, "apply_taxes must be a boolean")
      expect { described_class.new(calculate_projected_usage: nil) }
        .to raise_error(ArgumentError, "calculate_projected_usage must be a boolean")
      expect { described_class.new(with_zero_units_filters: nil) }
        .to raise_error(ArgumentError, "with_zero_units_filters must be a boolean")
      expect { described_class.new(skip_adjusted_fees: nil) }
        .to raise_error(ArgumentError, "skip_adjusted_fees must be a boolean")
    end
  end

  describe "context predicates" do
    it "returns whether the option matches a context" do
      expect(described_class.new(context: :current_usage)).to be_current_usage
      expect(described_class.new(context: :invoice_preview)).to be_invoice_preview
      expect(described_class.new(context: :recurring)).to be_recurring
      expect(described_class.new(context: :finalize)).to be_finalize
    end
  end
end
