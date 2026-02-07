local ReleaseDetails = require("updater.release_details")

describe("release_details module", function()
  before_each(function()
    -- Reset state before each test
    ReleaseDetails.clear_line_mapping()
    ReleaseDetails.set_all_tags({})
  end)

  describe("line_to_release mapping", function()
    it("should register and retrieve release lines", function()
      ReleaseDetails.register_release_line(5, "v1.0.0")
      ReleaseDetails.register_release_line(10, "v0.9.0")

      assert.equals("v1.0.0", ReleaseDetails.get_release_at_line(5))
      assert.equals("v0.9.0", ReleaseDetails.get_release_at_line(10))
    end)

    it("should return nil for unregistered lines", function()
      ReleaseDetails.register_release_line(5, "v1.0.0")

      assert.is_nil(ReleaseDetails.get_release_at_line(3))
      assert.is_nil(ReleaseDetails.get_release_at_line(7))
    end)

    it("should clear mappings", function()
      ReleaseDetails.register_release_line(5, "v1.0.0")
      ReleaseDetails.clear_line_mapping()

      assert.is_nil(ReleaseDetails.get_release_at_line(5))
    end)
  end)

  describe("navigable_lines", function()
    it("should track navigable lines from release registrations", function()
      ReleaseDetails.register_release_line(5, "v1.0.0")
      ReleaseDetails.register_release_line(10, "v0.9.0")
      ReleaseDetails.sort_navigable_lines()

      assert.equals(2, #ReleaseDetails.navigable_lines)
      assert.equals(5, ReleaseDetails.navigable_lines[1])
      assert.equals(10, ReleaseDetails.navigable_lines[2])
    end)

    it("should track navigable lines from direct registration", function()
      ReleaseDetails.register_navigable_line(3)
      ReleaseDetails.register_navigable_line(7)
      ReleaseDetails.sort_navigable_lines()

      assert.equals(2, #ReleaseDetails.navigable_lines)
      assert.equals(3, ReleaseDetails.navigable_lines[1])
      assert.equals(7, ReleaseDetails.navigable_lines[2])
    end)

    it("should sort navigable lines correctly", function()
      ReleaseDetails.register_navigable_line(10)
      ReleaseDetails.register_navigable_line(3)
      ReleaseDetails.register_navigable_line(7)
      ReleaseDetails.sort_navigable_lines()

      assert.equals(3, ReleaseDetails.navigable_lines[1])
      assert.equals(7, ReleaseDetails.navigable_lines[2])
      assert.equals(10, ReleaseDetails.navigable_lines[3])
    end)
  end)

  describe("release_lines", function()
    it("should track only release lines separately", function()
      ReleaseDetails.register_release_line(5, "v1.0.0")
      ReleaseDetails.register_navigable_line(3) -- commit line, not a release
      ReleaseDetails.register_release_line(10, "v0.9.0")
      ReleaseDetails.sort_navigable_lines()

      assert.equals(2, #ReleaseDetails.release_lines)
      assert.equals(3, #ReleaseDetails.navigable_lines)
    end)

    it("should get first release line", function()
      ReleaseDetails.register_navigable_line(3)
      ReleaseDetails.register_release_line(5, "v1.0.0")
      ReleaseDetails.register_release_line(10, "v0.9.0")
      ReleaseDetails.sort_navigable_lines()

      assert.equals(5, ReleaseDetails.get_first_release_line())
    end)

    it("should return nil when no release lines", function()
      ReleaseDetails.register_navigable_line(3)
      ReleaseDetails.register_navigable_line(7)
      ReleaseDetails.sort_navigable_lines()

      assert.is_nil(ReleaseDetails.get_first_release_line())
    end)
  end)

  describe("get_nearest_navigable_line", function()
    before_each(function()
      ReleaseDetails.register_navigable_line(5)
      ReleaseDetails.register_navigable_line(10)
      ReleaseDetails.register_navigable_line(15)
      ReleaseDetails.sort_navigable_lines()
    end)

    it("should return exact match", function()
      assert.equals(10, ReleaseDetails.get_nearest_navigable_line(10))
    end)

    it("should return nearest line when between lines", function()
      assert.equals(10, ReleaseDetails.get_nearest_navigable_line(8))
      assert.equals(10, ReleaseDetails.get_nearest_navigable_line(12))
    end)

    it("should return first line when before all lines", function()
      assert.equals(5, ReleaseDetails.get_nearest_navigable_line(1))
    end)

    it("should return last line when after all lines", function()
      assert.equals(15, ReleaseDetails.get_nearest_navigable_line(20))
    end)

    it("should return nil when no navigable lines", function()
      ReleaseDetails.clear_line_mapping()
      assert.is_nil(ReleaseDetails.get_nearest_navigable_line(10))
    end)
  end)

  describe("get_next_navigable_line", function()
    before_each(function()
      ReleaseDetails.register_navigable_line(5)
      ReleaseDetails.register_navigable_line(10)
      ReleaseDetails.register_navigable_line(15)
      ReleaseDetails.sort_navigable_lines()
    end)

    it("should return next line", function()
      assert.equals(10, ReleaseDetails.get_next_navigable_line(5))
      assert.equals(15, ReleaseDetails.get_next_navigable_line(10))
    end)

    it("should return last line when at end", function()
      assert.equals(15, ReleaseDetails.get_next_navigable_line(15))
    end)

    it("should return next line when between lines", function()
      assert.equals(10, ReleaseDetails.get_next_navigable_line(7))
    end)
  end)

  describe("get_prev_navigable_line", function()
    before_each(function()
      ReleaseDetails.register_navigable_line(5)
      ReleaseDetails.register_navigable_line(10)
      ReleaseDetails.register_navigable_line(15)
      ReleaseDetails.sort_navigable_lines()
    end)

    it("should return previous line", function()
      assert.equals(5, ReleaseDetails.get_prev_navigable_line(10))
      assert.equals(10, ReleaseDetails.get_prev_navigable_line(15))
    end)

    it("should return first line when at beginning", function()
      assert.equals(5, ReleaseDetails.get_prev_navigable_line(5))
    end)

    it("should return previous line when between lines", function()
      assert.equals(5, ReleaseDetails.get_prev_navigable_line(7))
    end)
  end)

  describe("all_tags and get_previous_tag", function()
    it("should set and use all tags", function()
      ReleaseDetails.set_all_tags({ "v1.2.0", "v1.1.0", "v1.0.0" })

      assert.equals(3, #ReleaseDetails.all_tags)
    end)

    it("should get previous tag in list", function()
      ReleaseDetails.set_all_tags({ "v1.2.0", "v1.1.0", "v1.0.0" })

      assert.equals("v1.1.0", ReleaseDetails.get_previous_tag("v1.2.0"))
      assert.equals("v1.0.0", ReleaseDetails.get_previous_tag("v1.1.0"))
    end)

    it("should return nil for last tag", function()
      ReleaseDetails.set_all_tags({ "v1.2.0", "v1.1.0", "v1.0.0" })

      assert.is_nil(ReleaseDetails.get_previous_tag("v1.0.0"))
    end)

    it("should return nil for unknown tag", function()
      ReleaseDetails.set_all_tags({ "v1.2.0", "v1.1.0", "v1.0.0" })

      assert.is_nil(ReleaseDetails.get_previous_tag("v2.0.0"))
    end)
  end)
end)
