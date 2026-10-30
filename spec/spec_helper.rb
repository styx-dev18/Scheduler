require "zeitwerk"

domain_only = !ARGV.empty? && ARGV.all? { |arg| arg.start_with?("spec/domain") }

if domain_only
  domain_loader = Zeitwerk::Loader.new
  domain_loader.push_dir(File.expand_path("../app/domain", __dir__))
  domain_loader.setup
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
