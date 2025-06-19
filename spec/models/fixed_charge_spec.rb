require 'rails_helper'

RSpec.describe FixedCharge, type: :model do
  let(:fixed_charge) { create(:fixed_charge) }

  describe "#code" do
    it "returns the add_on code" do
      expect(fixed_charge.code).to eq(fixed_charge.add_on.code)
    end
  end
end
