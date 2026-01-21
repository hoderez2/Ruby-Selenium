# frozen_string_literal: true

require "fileutils"
require "selenium-webdriver"
require_relative "pages/home_page"
require_relative "../pt_reporter"


RSpec.configure do |config|
  config.add_formatter("progress")

  # JUnit XML output for test management imports
  config.add_formatter("RspecJunitFormatter", "reports/rspec.xml")
end

RSpec.describe "PractiTest integration demo" do
  before(:each) do
    @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    options = Selenium::WebDriver::Chrome::Options.new
    options.add_argument("--headless=new")
    options.add_argument("--window-size=1400,900")

    service = Selenium::WebDriver::Service.chrome(path: ENV.fetch("CHROMEDRIVER_PATH", "chromedriver"))
    @driver = Selenium::WebDriver.for(:chrome, options: options, service: service)
    @driver.manage.timeouts.implicit_wait = 2
  end



  
  after(:each) do |example|
    FileUtils.mkdir_p("artifacts")

    screenshot_path = "artifacts/#{example.full_description.gsub(/[^\w\-]+/, "_")}.png"

    if example.exception
        @driver.save_screenshot(screenshot_path)
        puts "Saved screenshot: #{screenshot_path}"
    end

    passed = example.exception.nil?
    exit_code = passed ? 0 : 1

    reporter = PractiTestReporter.new(
        base_url: ENV.fetch("PT_BASE_URL"),         # https://api.practitest.com OR https://eu1-prod-api.practitest.app
        project_id: ENV.fetch("PT_PROJECT_ID"),
        api_token: ENV.fetch("PT_API_TOKEN"),
        developer_email: ENV.fetch("PT_EMAIL")
    )

    output = if passed
             "RSpec: PASSED"
           else
             "RSpec: FAILED\n#{example.exception.class}: #{example.exception.message}"
           end
    

    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started_at
    total_seconds = elapsed.ceil

    run_duration = format(
    "%02d:%02d:%02d",
    total_seconds / 3600,
    (total_seconds % 3600) / 60,
    total_seconds % 60
    )

    puts "Sending run-duration=#{run_duration}"

    set_id = ENV.fetch("PT_TESTSET_ID").to_i
    test_name = example.description

    instance_id = reporter.ensure_instance_for_test_name!(set_id: set_id, test_name: test_name)


           
    reporter.create_run(
        instance_id: instance_id,
        exit_code: exit_code,
        automated_output: output,
        run_duration: run_duration,
        attachments: (passed ? [] : [screenshot_path]) # attach screenshot only when failed
    )
    ensure
    @driver.quit if @driver
  end

  it "opens Example and validates the page" do
    page = HomePage.new(@driver)
    page.open
    expect(page.title).to include("Example Domain")
    expect(page.heading_text).to eq("Example Domain")
  end

  it "Test API" do
    page = HomePage.new(@driver)
    page.open
    expect(page.title).to include("Example Domain")
    expect(page.heading_text).to eq("Example Domain")
  end
end
