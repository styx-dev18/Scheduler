module PrometheusMetrics
  def scrape_metrics
    status, _headers, body = Yabeda::Prometheus::Exporter.call(
      "REQUEST_METHOD" => "GET", "PATH_INFO" => "/", "rack.input" => StringIO.new, "HTTP_ACCEPT" => "*/*"
    )
    raise "scrape failed with #{status}" unless status == 200

    body.each.to_a.join
  end

  def metric_sample(name, labels = nil)
    pattern = /^#{Regexp.escape(name)}#{Regexp.escape(labels) if labels}\s+(\S+)$/
    scrape_metrics[pattern, 1].to_f
  end
end

RSpec.configure { |config| config.include PrometheusMetrics }
