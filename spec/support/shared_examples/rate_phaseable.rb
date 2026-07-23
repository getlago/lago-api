# frozen_string_literal: true

# Expects the including spec to define:
#   let(:item) { ... }              - the rate-phase parent
#   let(:create_rate_phase) { ... } - ->(attributes) { create(:rate_phase, ...) }
RSpec.shared_examples "a rate phase parent" do
  describe "#rate_phase_for_cycle" do
    context "with a terminal (indefinite) phase" do
      let!(:first) { create_rate_phase.call(position: 1, billing_interval_cycle_count: 2) }
      let!(:terminal) { create_rate_phase.call(position: 2, billing_interval_cycle_count: nil) }

      it "returns the phase covering each cycle" do
        expect(item.rate_phase_for_cycle(0)).to eq(first)
        expect(item.rate_phase_for_cycle(1)).to eq(first)
        expect(item.rate_phase_for_cycle(2)).to eq(terminal)
        expect(item.rate_phase_for_cycle(99)).to eq(terminal)
      end
    end

    context "when all phases are finite" do
      before do
        create_rate_phase.call(position: 1, billing_interval_cycle_count: 2)
        create_rate_phase.call(position: 2, billing_interval_cycle_count: 3)
      end

      it "returns nil for cycles past the defined window" do
        expect(item.rate_phase_for_cycle(5)).to be_nil
      end
    end

    context "without any phase" do
      it "returns nil" do
        expect(item.rate_phase_for_cycle(0)).to be_nil
      end
    end
  end
end
