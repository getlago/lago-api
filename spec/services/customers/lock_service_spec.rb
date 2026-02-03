# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customers::LockService do
  let(:lock_service) { described_class.new(customer:) }
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }

  describe "#call" do
    subject { lock_service.call }

    context "when lock can be acquired" do
      it "takes an advisory lock" do
        expect(lock_service).not_to be_locked

        lock_service.call do
          expect(lock_service).to be_locked
        end

        expect(lock_service).not_to be_locked
      end
    end

    context "when lock cannot be acquired" do
      it "raises Customers::FailedToAcquireLock" do
        lock_service.call do
          second_lock_service = described_class.new(customer:, timeout_seconds: 0)

          expect do
            second_lock_service.call { nil }
          end.to raise_error(Customers::FailedToAcquireLock)
        end
      end
    end
  end

  describe "#locked?" do
    subject { lock_service.locked? }

    context "when the lock is taken" do
      it "returns true" do
        lock_service.call do
          expect(subject).to be true
        end
      end
    end

    context "when the lock is not taken" do
      it "returns false" do
        expect(subject).to be false
      end
    end
  end
end
