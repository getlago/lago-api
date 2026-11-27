# frozen_string_literal: true

namespace :invoices do
  desc "Fill expected_finalization_date"
  task fill_expected_finalization_date: :environment do
    Invoice.where(expected_finalization_date: nil).in_batches(of: 10_000).update_all(["expected_finalization_date = issuing_date, updated_at = ?", Time.current]) # rubocop:disable Rails/SkipsModelValidations
  end
end
