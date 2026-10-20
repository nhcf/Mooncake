// CPU-only failure injection for the production io_uring submission helper.
#include "mooncake-store/src/uring_submit.h"
#include <cassert>
#include <iostream>
#include <vector>

int main() {
    using mooncake::detail::submit_all_pending;
    auto run = [](unsigned initial, std::vector<int> returns, unsigned retries,
                  unsigned submitted, unsigned remaining, int error,
                  unsigned expected_yields) {
        unsigned pending = initial, calls = 0, yields = 0;
        auto result = submit_all_pending(
            [&] { return pending; },
            [&](unsigned n) {
                assert(n == pending && calls < returns.size());
                int ret = returns[calls++];
                if (ret > 0 && static_cast<unsigned>(ret) <= pending)
                    pending -= ret;
                return ret;
            },
            [&] { ++yields; }, retries);
        assert(result.submitted == submitted && result.pending == remaining);
        assert(result.error == error && yields == expected_yields);
        assert(calls == returns.size());
    };
    run(0, {}, 2, 0, 0, 0, 0);
    run(3, {1, 2}, 2, 3, 0, 0, 0);
    run(2, {-EINTR, -EAGAIN, 1, -ENOMEM, 1}, 2, 2, 0, 0, 3);
    run(2, {-EAGAIN, -EAGAIN, -EAGAIN}, 2, 0, 2, -EAGAIN, 2);
    run(2, {1, -EBADF}, 2, 1, 1, -EBADF, 0);
    run(2, {0}, 2, 0, 2, -EIO, 0);
    run(2, {3}, 2, 0, 2, -EIO, 0);
    std::cout << "PASS: 7 submission cases (CPU helper; no kernel io_uring)\n";
}
