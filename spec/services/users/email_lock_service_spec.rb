# frozen_string_literal: true

require "rails_helper"

RSpec.describe Users::EmailLockService, transaction: false do
  def try_lock(email)
    described_class.call(email:, timeout_seconds: 0) { :locked }.value
  end

  it "yields inside a transaction and returns the block's value" do
    value = described_class.call(email: "jane@acme.com") { ApplicationRecord.connection.transaction_open? }.value

    expect(value).to be(true)
  end

  context "when another process holds the lock of a mailbox" do
    it "blocks every spelling of that mailbox, without naming it in the error" do
      with_email_lock("jane@acme.com") do
        ["JANE@acme.com", "jane+x@acme.com", "ja​ne@acme.com"].each do |email|
          expect { try_lock(email) }.to raise_error(BaseLockService::FailedToAcquireLock) { |error|
            expect(error.message).not_to include("jane")
          }
        end
      end
    end

    it "does not block another mailbox" do
      with_email_lock("jane@acme.com") do
        expect(try_lock("bob@acme.com")).to eq(:locked)
      end
    end

    it "uses the single 64-bit key form, which never collides with with_advisory_lock" do
      with_email_lock("jane@acme.com") do
        locks = ApplicationRecord.connection.select_rows("SELECT locktype, objsubid FROM pg_locks WHERE locktype = 'advisory'")

        expect(locks).to include(["advisory", 1])
      end
    end
  end

  it "releases the lock when the transaction ends" do
    with_email_lock("jane@acme.com") { nil }

    expect(try_lock("jane@acme.com")).to eq(:locked)
  end

  it "joins an open transaction and holds the lock until it ends" do
    ApplicationRecord.transaction do
      described_class.call(email: "jane@acme.com") { nil }

      thread = Thread.new do
        ApplicationRecord.connection_pool.with_connection { try_lock("jane@acme.com") }
      rescue BaseLockService::FailedToAcquireLock
        :blocked
      end

      expect(thread.value).to eq(:blocked)
    end
  end
end
