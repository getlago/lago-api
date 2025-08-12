# frozen_string_literal: true

require "rails_helper"

RSpec.describe JobScheduleOverride, type: :model do
  subject(:job_schedule_override) { build(:job_schedule_override) }

  it { expect(described_class).to be_soft_deletable }

  it { is_expected.to belong_to(:organization) }

  it { is_expected.to validate_presence_of(:job_name) }
  it { is_expected.to validate_numericality_of(:frequency_secods).only_integer.is_greater_than(0) }
  it { is_expected.to validate_uniqueness_of(:job_name).scoped_to(:organization_id) }

  describe "Scopes" do
    describe ".enabled" do
      subject { described_class.enabled }

      let(:enabled_override) { create(:job_schedule_override) }
      let(:disabled_override) { create(:job_schedule_override, :disabled) }

      before do
        enabled_override
        disabled_override
      end

      it { is_expected.to eq [enabled_override] }
    end
  end
end
