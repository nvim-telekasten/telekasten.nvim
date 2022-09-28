local M = {}
local date = require("taglinks.date")

--- returns the day of week (1..Monday, ..., 7..Sunday) for Dec, 31st of year
--- see https://webspace.science.uu.nl/~gent0113/calendar/isocalendar.htm
--- see https://en.wikipedia.org/wiki/ISO_week_date
M.dow_for_year = function(year)
    return (
        year
        + math.floor(year / 4)
        - math.floor(year / 100)
        + math.floor(year / 400)
    ) % 7
end

M.weeks_in_year = function(year)
    local d = 0
    local dy = M.dow_for_year(year) == 4 -- current year ends Thursday
    local dyy = M.dow_for_year(year - 1) == 3 -- previous year ends Wednesday
    if dy or dyy then
        d = 1
    end
    return 52 + d
end

M.days_in_year = function(year)
    local t = os.time({ year = year, month = 12, day = 31 })
    return os.date("*t", t).yday
end

M.date_from_doy = function(year, doy)
    local ret = {
        year = year,
        month = 1,
        day = doy,
    }
    -- january is clear immediately
    if doy < 32 then
        return ret
    end

    local dmap = {
        [1] = 31,
        [2] = 28, -- will be fixed further down
        [3] = 31,
        [4] = 30,
        [5] = 31,
        [6] = 30,
        [7] = 31,
        [8] = 31,
        [9] = 30,
        [10] = 31,
        [11] = 30,
        [12] = 31,
    }
    if M.days_in_year(year) == 366 then
        dmap[2] = 29
    end

    for month, d in pairs(dmap) do
        doy = doy - d
        if doy < 0 then
            ret.day = doy + d
            ret.month = month
            return ret
        end
    end
    return ret -- unreachable if input values are sane
end

-- the algo on wikipedia seems wrong, so we opt for full-blown luadate
M.isoweek_to_date = function(year, isoweek)
    local ret = date(year .. "-W" .. string.format("%02d", isoweek) .. "-1")
    return {
        year = ret:getyear(),
        month = ret:getmonth(),
        day = ret:getday(),
    }
end

local function check_isoweek(year, isoweek, ydate)
    print("***********   KW " .. isoweek .. " " .. year .. ": ")
    -- local ret = M.weeknumber_to_date(year, isoweek)
    local ret = M.isoweek_to_date(year, isoweek)
    local result = ret.year == ydate.year
        and ret.month == ydate.month
        and ret.day == ydate.day
    print(
        ret.year
            .. "-"
            .. ret.month
            .. "-"
            .. ret.day
            .. " == "
            .. ydate.year
            .. "-"
            .. ydate.month
            .. "-"
            .. ydate.day
            .. " : "
            .. tostring(result)
    )
end

M.run_tests = function()
    print(check_isoweek(2020, 1, { year = 2019, month = 12, day = 30 })) -- 30.12.2019
    print(check_isoweek(2020, 52, { year = 2020, month = 12, day = 21 })) -- 21.12.2020
    print(check_isoweek(2020, 53, { year = 2020, month = 12, day = 28 })) -- 28.12.2020
    print(check_isoweek(2021, 1, { year = 2021, month = 1, day = 4 })) -- 4.1.2020
    print(check_isoweek(2021, 52, { year = 2021, month = 12, day = 27 })) -- 27.12.2021
    print(check_isoweek(2022, 1, { year = 2022, month = 1, day = 3 })) -- 3.1.2022
end

-- M.run_tests()

return M
