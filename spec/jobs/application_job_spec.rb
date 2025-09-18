# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationJob do
  let(:job_class) do
    Class.new(ApplicationJob) do
      def perform(arg1, arg2, option: "default")
      end
    end
  end

  describe "#perform_after_commit" do
    it "performs the job after the commit" do
      ApplicationRecord.transaction do
        job_class.perform_after_commit(1, 2, option: "custom")
        expect(job_class).not_to have_been_enqueued
      end

      expect(job_class).to have_been_enqueued.with(1, 2, option: "custom")
    end
  end
end
