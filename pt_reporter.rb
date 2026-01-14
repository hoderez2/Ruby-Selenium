# frozen_string_literal: true

require "net/http"
require "json"
require "base64"
require "uri"
require "openssl"

class PractiTestReporter
  def initialize(base_url:, project_id:, api_token:, developer_email:)
    @base_url = base_url.sub(/\/$/, "")
    @project_id = project_id
    @api_token = api_token
    @developer_email = developer_email
  end

  def create_run(instance_id:, exit_code:, run_duration: nil, automated_output: nil, attachments: [])
    uri = URI("#{@base_url}/api/v2/projects/#{@project_id}/runs.json")

    payload = {
      data: {
        type: "instances",
        attributes: {
          "instance-id": instance_id,
          "exit-code": exit_code,
          "run-duration": run_duration,
          "automated-execution-output": automated_output
        }.compact
      }
    }

# puts "Sending run-duration=#{run_duration}"

    if attachments.any?
      payload[:data][:files] = {
        data: attachments.map do |path|
          {
            filename: File.basename(path),
            content_encoded: Base64.strict_encode64(File.binread(path))
          }
        end
      }
    end

    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req["PTToken"] = @api_token
    req["developer_email"] = @developer_email
    req.body = JSON.generate(payload)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER

    store = OpenSSL::X509::Store.new
    store.add_file(ENV["SSL_CERT_FILE"] || "/etc/ssl/cert.pem")
    http.cert_store = store

    http.verify_callback = lambda do |preverify_ok, store_ctx|
      return true if preverify_ok
      store_ctx.error == OpenSSL::X509::V_ERR_UNABLE_TO_GET_CRL
    end

    res = http.start { |h| h.request(req) }

    unless res.is_a?(Net::HTTPSuccess) || res.is_a?(Net::HTTPCreated)
      raise "PractiTest API error #{res.code}: #{res.body}"
    end

    res.body
  end
end
