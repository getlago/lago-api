# frozen_string_literal: true

namespace :invoices do
  desc "Fill expected_finalization_date"
  task fill_expected_finalization_date: :environment do
    Invoice.in_batches(of: 10_000).update_all("expected_finalization_date = COALESCE(expected_finalization_date, issuing_date)") # rubocop:disable Rails/SkipsModelValidations
  end
end
