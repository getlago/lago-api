# frozen_string_literal: true

require 'benchmark/ips'

expression = "((ended_at - started_at) * replicas) / 3600"
ended_at = 2.to_d
started_at = 1.to_d
replicas = 10.to_d
divisor = 3600.to_d
parsed = LagoFormulaParser.new.parse(expression)
context = {"ended_at" => ended_at, "started_at" => started_at, "replicas" => replicas}

puts parsed.evaluate(context)

Benchmark.ips do |x|
  x.report("without formula") { (ended_at - started_at) * replicas / divisor }

  x.report("with formula") { parsed.evaluate(context) }

  x.compare!
end
