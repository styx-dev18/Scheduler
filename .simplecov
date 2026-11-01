SimpleCov.start "rails" do
  enable_coverage :branch
  add_group "Domain", "app/domain"
  add_group "Services", "app/services"
end

if ENV.fetch("COVERAGE") { ENV["CI"] } == "true"
  thresholds = { "Domain" => { line: 90, branch: 85 }, "Services" => { line: 90, branch: 85 } }

  SimpleCov.at_exit do
    result = SimpleCov.result
    result.format!
    failures = thresholds.flat_map do |name, minimum|
      stats = result.groups.fetch(name).coverage_statistics
      minimum.filter_map do |criterion, floor|
        actual = stats.fetch(criterion).percent
        "#{name} #{criterion} coverage #{actual.round(2)}% is below minimum #{floor}%" if actual < floor
      end
    end
    failures.each { |message| warn message }
    exit(SimpleCov::ExitCodes::MINIMUM_COVERAGE) if failures.any?
  end
end
