# frozen_string_literal: true

class HomePage
  def initialize(driver)
    @driver = driver
  end

  def open
    @driver.navigate.to("https://example.com")
  end

  def title
    @driver.title
  end

  def heading_text
    @driver.find_element(css: "h1").text
  end
end
