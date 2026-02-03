# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customers::LockService do
  let(:lock_service) { described_class.new(customer:, timeout_seconds:) }
  let(:customer) { create(:customer) }
  let(:timeout_seconds) { 5.seconds }

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

    context "when lock cannot be acquired", transaction: false do
      let(:lock_released_after) { 2.seconds }
      let(:timeout_seconds) { 0.seconds }

      around do |test|
        customer_id = customer.id
        queue = Queue.new
        thread = start_lock_thread(queue, customer_id)
        sleep 0.5
        test.run
      ensure
        stop_thread(thread, queue) if thread
      end

      def start_lock_thread(queue, customer_id)
        Thread.start do
          start_time = Time.zone.now
          ApplicationRecord.transaction do
            ApplicationRecord.with_advisory_lock!("customer-#{customer_id}", transaction: true) do
              until queue.size > 0 || Time.zone.now - start_time > lock_released_after
                sleep 0.01
              end
            end
          end
        end
      end

      def stop_thread(thread, queue)
        queue.push(true)
        thread.join
      end

      it "raises a Customers::FailedToAcquireLock error" do
        expect do
          lock_service.call { nil }
        end.to raise_error(Customers::FailedToAcquireLock, "Failed to acquire lock customer-#{customer.id}")
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
