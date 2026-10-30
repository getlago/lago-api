# frozen_string_literal: true

require "rails_helper"

RSpec.describe PendingViesCheck, type: :model do
  subject(:pending_vies_check) { build(:pending_vies_check) }

  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:billing_entity)
      expect(subject).to belong_to(:customer)
    end
  end

  describe "validations" do
    subject(:pending_vies_check) { create(:pending_vies_check) }

    it do
      expect(subject).to validate_uniqueness_of(:customer_id).ignoring_case_sensitivity
      expect(subject).to validate_numericality_of(:attempts_count).is_greater_than_or_equal_to(0)
      expect(subject).to validate_inclusion_of(:last_error_type).in_array(described_class::KNOWN_ERROR_TYPES).allow_nil
    end
  end

  describe ".error_type_for" do
    it "maps Valvat exceptions to error type strings" do
      expect(described_class.error_type_for(Valvat::RateLimitError.new("error", :vies))).to eq("rate_limit")
      expect(described_class.error_type_for(Valvat::Timeout.new("error", :vies))).to eq("timeout")
      expect(described_class.error_type_for(Valvat::BlockedError.new("error", :vies))).to eq("blocked")
      expect(described_class.error_type_for(Valvat::InvalidRequester.new("error", :vies))).to eq("invalid_requester")
      expect(described_class.error_type_for(Valvat::ServiceUnavailable.new("error", :vies))).to eq("service_unavailable")
      expect(described_class.error_type_for(Valvat::HTTPError.new("The VIES web service returned the error: 307 ", :vies))).to eq("service_unavailable")
      expect(described_class.error_type_for(Valvat::MemberStateUnavailable.new("error", :vies))).to eq("member_state_unavailable")
    end

    it "maps transport timeouts to timeout" do
      expect(described_class.error_type_for(Net::OpenTimeout.new)).to eq("timeout")
      expect(described_class.error_type_for(Net::ReadTimeout.new)).to eq("timeout")
      expect(described_class.error_type_for(Net::WriteTimeout.new)).to eq("timeout")
    end

    it "maps other transport failures to service_unavailable" do
      expect(described_class.error_type_for(Errno::ECONNRESET.new)).to eq("service_unavailable")
      expect(described_class.error_type_for(Errno::ENETUNREACH.new)).to eq("service_unavailable")
      expect(described_class.error_type_for(Errno::ETIMEDOUT.new)).to eq("service_unavailable")
      expect(described_class.error_type_for(Errno::ECONNABORTED.new)).to eq("service_unavailable")
      expect(described_class.error_type_for(EOFError.new)).to eq("service_unavailable")
      expect(described_class.error_type_for(OpenSSL::SSL::SSLError.new)).to eq("service_unavailable")
    end

    it "returns 'unknown' for unmapped Valvat lookup errors" do
      expect(described_class.error_type_for(Valvat::UnknownLookupError.new("SERVER_BUSY", :vies))).to eq("unknown")
    end

    it "returns 'unknown' for unmapped exceptions" do
      expect(described_class.error_type_for(StandardError.new)).to eq("unknown")
    end
  end
end
