# frozen_string_literal: true

require "rails_helper"

require "rake"

RSpec.describe "invoices:fill_expected_finalization_date" do # rubocop:disable RSpec/DescribeClass
  let(:task) { Rake::Task["invoices:fill_expected_finalization_date"] }

  let(:invoice_without_date) do
    create(:invoice, issuing_date: Date.new(2026, 10, 1), expected_finalization_date: nil, updated_at: 1.day.ago)
  end
  let(:invoice_with_date) do
    create(:invoice, issuing_date: Date.new(2026, 10, 1), expected_finalization_date: Date.new(2026, 10, 5), updated_at: 1.day.ago)
  end

  before do
    invoice_without_date
    invoice_with_date
    Rake.application.rake_require("tasks/invoices")
    Rake::Task.define_task(:environment)
    task.reenable
  end

  it "fills the missing expected finalization dates from the issuing date" do
    freeze_time do
      dated_invoice_updated_at = invoice_with_date.updated_at
      task.invoke

      expect(invoice_without_date.reload).to have_attributes(expected_finalization_date: Date.new(2026, 10, 1), updated_at: Time.current)
      expect(invoice_with_date.reload).to have_attributes(expected_finalization_date: Date.new(2026, 10, 5), updated_at: dated_invoice_updated_at)
    end
  end
end
