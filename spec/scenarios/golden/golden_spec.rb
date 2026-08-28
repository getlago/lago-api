# frozen_string_literal: true

require "rails_helper"

# Driver for the golden billing matrix.
#
# The rows live in matrix/*.yml and are interpreted by GoldenRunner; this file only turns each row
# into an example. Adding coverage means adding a row, not writing Ruby — which is what lets the
# suite be maintained as data and run in CI with no model in the loop.
#
#   bundle exec rspec spec/scenarios/golden                     # whole matrix
#   bundle exec rspec spec/scenarios/golden -e "b01/volume"     # one row
#   bundle exec rspec spec/scenarios/golden -e "B14"            # one block
describe "Golden billing matrix" do
  include GoldenRunner

  let(:organization) { create(:organization, webhook_url: nil) }

  describe "matrix integrity" do
    it "is not empty" do
      # A silently-empty matrix must not read as a passing suite.
      expect(GoldenMatrix.matrix_files).not_to be_empty, "no matrix files found in #{GoldenMatrix.dir}/matrix"
      expect(GoldenMatrix.rows).not_to be_empty, "matrix files contain no rows"
    end

    it "validates every row against schema.json" do
      errors = GoldenMatrix.schema_errors
      expect(errors).to be_empty, "#{errors.size} row(s) violate the schema:\n\n#{errors.join("\n\n")}"
    end

    it "passes the matrix lints" do
      errors = GoldenMatrix.lint_errors
      expect(errors).to be_empty, "#{errors.size} lint failure(s):\n\n- #{errors.join("\n- ")}"
    end

    it "reports the census" do
      census = GoldenMatrix.census
      lines = census.map do |block, stats|
        format(
          "  %-4s rows=%-4d cells=%-4d live=%-4d characterization=%d",
          block, stats[:rows], stats[:cells], stats[:live], stats[:characterization]
        )
      end
      RSpec.configuration.reporter.message(
        "\nGolden matrix census (#{GoldenMatrix.rows.size} rows across #{census.size} block(s)):\n#{lines.join("\n")}"
      )

      expect(census.values.sum { |s| s[:rows] }).to eq(GoldenMatrix.rows.size)
    end
  end

  # Every row in the matrix becomes an example in THIS ONE FILE, and parallel_tests splits work by
  # file — so it cannot divide the golden suite at all. `GOLDEN_SHARD=<n>/<total>` selects a slice
  # here instead, which is what lets several lanes run the matrix at once, each against its own
  # database (see dev/golden/parallel.rb).
  #
  # Round-robin, not contiguous slices: rows differ tenfold in cost and the expensive ones cluster by
  # block — progressive billing, multi-period timelines — so a contiguous split would hand one lane
  # all of B5 and another all of B14, and the run would take as long as its slowest lane.
  def self.golden_shard(rows)
    spec = ENV["GOLDEN_SHARD"]
    return rows if spec.blank?

    index, total = spec.split("/").map(&:to_i)
    raise ArgumentError, "GOLDEN_SHARD must be <n>/<total>, got #{spec.inspect}" unless index&.positive? && total.to_i.positive?

    rows.each_with_index.select { |_row, position| position % total == index - 1 }.map(&:first)
  end

  golden_shard(GoldenMatrix.rows).group_by { |row| row["block"] }.sort.each do |block, block_rows|
    describe block do
      block_rows.each do |row|
        metadata = {}
        metadata[:premium] = true if row["premium"]
        # idempotent_transaction refuses to run inside an open transaction, so rows that reach it
        # (progressive billing) need DatabaseCleaner's deletion strategy instead.
        metadata[:transaction] = false if row["no_transaction"]

        it row["id"], **metadata do
          run_golden_row(row)
        end
      end
    end
  end
end
