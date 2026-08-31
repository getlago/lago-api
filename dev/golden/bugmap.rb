# frozen_string_literal: true

# Counts fix-commit density per golden block and writes spec/scenarios/golden/bugmap.json.
#
# Runs on the HOST, not in the container: `api` is a git submodule whose real .git directory is not
# mounted into the container, so git is unavailable there.
#
#   ruby dev/golden/bugmap.rb
#
# The output feeds the RISK column of `rake golden:ledger`. Commit it so RISK is reproducible, and
# regenerate every few months or after a refactor moves services between blocks.

# A standalone host script run with the system ruby, not Rails code: stdout and abort are its
# interface.
# rubocop:disable Rails/Output, Rails/Exit, Lint/RedundantRequireStatement
require "yaml"
require "json"
require "pathname"

SINCE = ENV.fetch("GOLDEN_BUGMAP_SINCE", "2024-01-01")
ROOT = Pathname.new(__dir__).join("../..").expand_path
BLOCKS = ROOT.join("spec/scenarios/golden/blocks.yml")
OUTPUT = ROOT.join("spec/scenarios/golden/bugmap.json")

unless system("git", "-C", ROOT.to_s, "rev-parse", "--git-dir", out: File::NULL, err: File::NULL)
  abort "not a git repository: #{ROOT} — run this on the host, not in the container"
end

blocks = YAML.safe_load_file(BLOCKS, aliases: true)

counts = blocks.to_h do |block|
  paths = Array(block["services"]).select { |path| ROOT.join(path).exist? }
  if paths.empty?
    warn "#{block["id"]}: no existing service paths declared — risk will be blank"
    next [block["id"], nil]
  end

  log = IO.popen(["git", "-C", ROOT.to_s, "log", "--since=#{SINCE}", "--pretty=format:%s", "--", *paths], &:read)
  # Commit subjects carry UTF-8; the host's system ruby may default to US-ASCII.
  log = log.dup.force_encoding("UTF-8").scrub("")
  [block["id"], log.lines.count { |line| line.match?(/\A(fix|bug)/i) }]
end

missing_paths = blocks.flat_map do |block|
  Array(block["services"]).reject { |path| ROOT.join(path).exist? }.map { |path| "#{block["id"]}: #{path}" }
end

OUTPUT.write(JSON.pretty_generate(
  "since" => SINCE,
  "generated_from" => `git -C #{ROOT} rev-parse --short HEAD`.strip,
  "stale_service_paths" => missing_paths,
  "blocks" => counts
) + "\n")

puts "wrote #{OUTPUT.relative_path_from(ROOT)} (since #{SINCE})"
counts.sort_by { |_id, count| -(count || 0) }.each { |id, count| puts format("  %-5s %s", id, count || "—") }
warn "\n#{missing_paths.size} declared service path(s) no longer exist — update blocks.yml:\n  #{missing_paths.join("\n  ")}" if missing_paths.any?
# rubocop:enable Rails/Output, Rails/Exit, Lint/RedundantRequireStatement
