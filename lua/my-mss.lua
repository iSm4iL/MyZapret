-- Scope this function to test destination IPs; MSS applies for the whole TCP connection.
function my_mss(ctx, desync)
    local tcp = desync.dis.tcp
    if not tcp or bitand(tcp.th_flags, TH_SYN) == 0 then return VERDICT_PASS end
    local size = tonumber(desync.arg.size)
    if not size or size % 1 ~= 0 or size < 256 or size > 1460 then error('my_mss: invalid size') end
    for _, opt in ipairs(tcp.options or {}) do
        if opt.kind == 2 and type(opt.data) == 'string' and #opt.data == 2 then
            local a, b = opt.data:byte(1, 2)
            if a * 256 + b > size then
                opt.data = string.char(math.floor(size / 256), size % 256)
                return VERDICT_MODIFY
            end
            return VERDICT_PASS
        end
    end
    return VERDICT_PASS
end
