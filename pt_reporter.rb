# frozen_string_literal: true

require "net/http"
require "json"
require "base64"
require "uri"
require "openssl"
require "cgi"

class PractiTestReporter
  def initialize(base_url:, project_id:, api_token:, developer_email:)
    @base_url = base_url.sub(/\/$/, "")
    @project_id = project_id
    @api_token = api_token
    @developer_email = developer_email
  end

  def request_json(method:, path:, payload: nil)
    uri = URI("#{@base_url}#{path}")

    req =
      case method
      when :get
        Net::HTTP::Get.new(uri)
      when :post
        r = Net::HTTP::Post.new(uri)
        r.body = JSON.generate(payload) if payload
        r
      else
        raise ArgumentError, "Unsupported method: #{method}"
      end

    req["Content-Type"] = "application/json"
    req["PTToken"] = @api_token
    req["developer_email"] = @developer_email

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

  JSON.parse(res.body)
end


  # --- Helpers ---
def get_json(path)
  request_json(method: :get, path: path)
end

def post_json(path, payload)
  request_json(method: :post, path: path, payload: payload)
end


# --- Tests ---
  def find_test_id_by_name_exact(name)
    q = CGI.escape(name)
    data = get_json("/api/v2/projects/#{@project_id}/tests.json?name_exact=#{q}")
    first = data["data"]&.first
    first && first["id"].to_i
  end

  def create_api_test(name)
    attrs = {
      "name" => name,
      "test-type" => "ApiTest"
    }
    attrs["author-id"] = ENV["PT_AUTHOR_ID"].to_i if ENV["PT_AUTHOR_ID"] && !ENV["PT_AUTHOR_ID"].empty?

    payload = { data: { type: "tests", attributes: attrs } }
    res = post_json("/api/v2/projects/#{@project_id}/tests.json", payload)
    res.dig("data", "id").to_i
  end

   # --- Instances ---
  def find_instance_id_in_set_by_name_exact(set_id, name)
    q = CGI.escape(name)
    data = get_json("/api/v2/projects/#{@project_id}/instances.json?set-ids=#{set_id}&name_exact=#{q}")
    first = data["data"]&.first
    first && first["id"].to_i
  end

# --- Main: ensure everything exists ---
  def ensure_instance_for_test_name!(set_id:, test_name:)
    test_id = find_test_id_by_name_exact(test_name) || create_api_test(test_name)
    find_instance_id_in_set_by_name_exact(set_id, test_name) || create_instance(set_id: set_id, test_id: test_id)
  end


  def create_instance(set_id:, test_id:)
    payload = {
      data: {
        type: "instances",
        attributes: {
          "set-id" => set_id,
          "test-id" => test_id
        }
      }
    }
    res = post_json("/api/v2/projects/#{@project_id}/instances.json", payload)
    res.dig("data", "id").to_i
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
