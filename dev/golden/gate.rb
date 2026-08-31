#!/usr/bin/env ruby
# frozen_string_literal: true

# Decides whether a golden run's failures are the DECLARED ones. The findings ledger lists rows
# that are deliberately red (`red_pins:` — they assert correct behaviour and stay failing until
# the defect is fixed), so a run is acceptable exactly when its failures and the declaration
# agree, in both directions:
#
#   a failure not declared red    -> a new defect or a broken row; the run fails
#   a declared red that PASSED    -> behaviour changed under the finding; the ledger entry is due
#                                    an update, and accepting the green silently would erase the
#                                    defect's one tripwire; the run fails
#
# Only rows that RAN are judged, so a shard that never saw a declared-red row says nothing about
# it. Failures in examples that are not matrix rows (harness, legality) are never expected.
#
#   bundle exec rspec spec/scenarios/golden --format json --out tmp/golden_result.json || true
#   ruby dev/golden/gate.rb tmp/golden_result.json
#
# Plain ruby on purpose: CI calls it after rspec exits, with no Rails boot.

# rubocop:disable Rails/Output, Rails/Exit
require "json"
require "yaml"

LEDGER = File.expand_path("../../spec/scenarios/golden/findings.yml", __dir__)
ROW_ID = %r{\bb\d+/\S+\z}

abort "usage: dev/golden/gate.rb <rspec-json-result> [more results...]" if ARGV.empty?

examples = ARGV.flat_map { |path| JSON.parse(File.read(path)).fetch("examples") }

ran = examples.filter_map { |example| example.fetch("full_description")[ROW_ID] }
failed_rows = examples.filter_map do |example|
  example.fetch("full_description")[ROW_ID] if example.fetch("status") == "failed"
end
failed_other = examples.select do |example|
  example.fetch("status") == "failed" && example.fetch("full_description")[ROW_ID].nil?
end

declared = YAML.safe_load_file(LEDGER, aliases: true)
  .reject { |entry| entry["status"] == "withdrawn" }
  .flat_map { |entry| Array(entry["red_pins"]) }

unexpected_failures = failed_rows - declared
unexpected_passes = (declared & ran) - failed_rows

puts "#{examples.size} example(s): #{failed_rows.size} row failure(s) " \
     "(#{(failed_rows & declared).size} declared red), #{failed_other.size} non-row failure(s)"

problems = []
if failed_other.any?
  problems << "harness/legality failures — never expected:"
  failed_other.each { |example| problems << "  #{example.fetch("full_description")}" }
end
if unexpected_failures.any?
  problems << "row failures not declared red in findings.yml — a new defect or a broken row:"
  unexpected_failures.sort.each { |id| problems << "  #{id}" }
end
if unexpected_passes.any?
  problems << "declared-red rows that PASSED — behaviour changed; update the finding (or its " \
              "red_pins) instead of pocketing the green:"
  unexpected_passes.sort.each { |id| problems << "  #{id}" }
end

if problems.any?
  puts problems
  exit 1
end

puts "gate clean: every failure is a declared red, every declared red that ran is still red"
# rubocop:enable Rails/Output, Rails/Exit
