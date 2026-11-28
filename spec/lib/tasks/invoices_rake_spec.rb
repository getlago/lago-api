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

  it "fills the missing expected finalization dates from the issuing date and leaves updated_at unchanged" do
    expect { task.invoke }.to not_change { invoice_without_date.reload.updated_at }
      .and not_change { invoice_with_date.reload.updated_at }

    expect(invoice_without_date.expected_finalization_date).to eq(Date.new(2026, 10, 1))
    expect(invoice_with_date.expected_finalization_date).to eq(Date.new(2026, 10, 5))
  end
end
