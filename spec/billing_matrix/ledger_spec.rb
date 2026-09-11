# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../billing_matrix/ledger"

RSpec.describe BillingMatrix::Ledger do
  let(:directory) { Dir.mktmpdir("matrix-ledger") }
  let(:ledger_path) { File.join(directory, "ledger.yml") }

  before { File.write(ledger_path, "[]\n") }
  after { FileUtils.remove_entry(directory) }

  def run_ledger(verdict, canaries_total: 1, canaries_unproven: 0)
    entries = YAML.safe_load_file(ledger_path, permitted_classes: [Date])
    results = {"run" => {"summary" => {"canaries_total" => canaries_total, "canaries_unproven" => canaries_unproven}},
               "rows" => [{"id" => "smoke/example", "area" => "smoke", "verdict" => verdict, "error" => "setup failed"}]}
    ledger = described_class.new(results:, entries:, today: Date.new(2026, 9, 11))
    ledger.run(ledger: ledger_path, apply: true, format: "text")
  end

  it "reports failures and fixes once, then silently prunes a fixed entry" do
    expect { run_ledger("failed") }.to output(/newly failing \(1\)/).to_stdout
    expect { run_ledger("failed") }.to output("\n").to_stdout
    expect { run_ledger("passed") }.to output(/fixed \(1\)/).to_stdout
    expect { run_ledger("passed") }.to output("\n").to_stdout
    expect(YAML.safe_load_file(ledger_path)).to eq([])
  end

  it "reports a recurrence while preserving the original first-seen date" do
    original = [{"id" => "smoke/example", "status" => "fixed", "first_seen" => "2026-08-26", "fixed_on" => "2026-09-10"}]
    File.write(ledger_path, YAML.dump(original))
    expect { run_ledger("failed") }.to output(/failing again \(1\)/).to_stdout
    expect(YAML.safe_load_file(ledger_path).first).to include("status" => "failed", "first_seen" => "2026-08-26")
  end

  it "reports scenario errors without marking known failures as fixed" do
    original = [{"id" => "smoke/example", "status" => "failed", "first_seen" => "2026-08-26"}]
    File.write(ledger_path, YAML.dump(original))
    expect { run_ledger("errored") }.to output(/errored \(1\).*setup failed/m).to_stdout
    expect(YAML.safe_load_file(ledger_path)).to eq(original)
  end

  it "refuses to update the ledger when a canary is unproven" do
    expect { expect(run_ledger("failed", canaries_unproven: 1)).to eq(2) }.to output(/refusing to apply/).to_stderr
    expect(File.read(ledger_path)).to eq("[]\n")
  end

  it "refuses to update the ledger without canaries" do
    expect { expect(run_ledger("failed", canaries_total: 0)).to eq(2) }.to output(/no canaries/).to_stderr
    expect(File.read(ledger_path)).to eq("[]\n")
  end
end
