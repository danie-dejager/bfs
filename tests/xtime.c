// Copyright © Tavian Barnes <tavianator@tavianator.com>
// SPDX-License-Identifier: 0BSD

#include "tests.h"

#include "bfs.h"
#include "diag.h"
#include "xtime.h"

#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <time.h>

static bool tm_equal(const struct tm *tma, const struct tm *tmb) {
	return tma->tm_year == tmb->tm_year
		&& tma->tm_mon == tmb->tm_mon
		&& tma->tm_mday == tmb->tm_mday
		&& tma->tm_hour == tmb->tm_hour
		&& tma->tm_min == tmb->tm_min
		&& tma->tm_sec == tmb->tm_sec
		&& tma->tm_wday == tmb->tm_wday
		&& tma->tm_yday == tmb->tm_yday
		&& tma->tm_isdst == tmb->tm_isdst;
}

/** Check one xgetdate() result. */
static bool check_one_xgetdate(const char *str, int error, time_t expected) {
	struct timespec ts;
	int ret = xgetdate(str, &ts);

	if (error) {
		return bfs_echeck(ret == -1 && errno == error, "xgetdate('%s')", str);
	} else {
		return bfs_echeck(ret == 0, "xgetdate('%s')", str)
			&& bfs_check(ts.tv_sec == expected && ts.tv_nsec == 0,
				"xgetdate('%s'): %jd.%09jd != %jd",
				str, (intmax_t)ts.tv_sec, (intmax_t)ts.tv_nsec, (intmax_t)expected);
	}
}

/** xgetdate() tests. */
static void check_xgetdate(void) {
	check_one_xgetdate("", EINVAL, 0);
	check_one_xgetdate("????", EINVAL, 0);
	check_one_xgetdate("1991", EINVAL, 0);
	check_one_xgetdate("1991-??", EINVAL, 0);
	check_one_xgetdate("1991-12", EINVAL, 0);
	check_one_xgetdate("1991-12-", EINVAL, 0);
	check_one_xgetdate("1991-12-??", EINVAL, 0);
	check_one_xgetdate("1991-12-14", 0, 692668800);
	check_one_xgetdate("1991-12-14-", EINVAL, 0);
	check_one_xgetdate("1991-12-14T", EINVAL, 0);
	check_one_xgetdate("1991-12-14T??", EINVAL, 0);
	check_one_xgetdate("1991-12-14T10", 0, 692704800);
	check_one_xgetdate("1991-12-14T10:??", EINVAL, 0);
	check_one_xgetdate("1991-12-14T10:11", 0, 692705460);
	check_one_xgetdate("1991-12-14T10:11:??", EINVAL, 0);
	check_one_xgetdate("1991-12-14T10:11:12", 0, 692705472);
	check_one_xgetdate("1991-12-14T10Z", 0, 692704800);
	check_one_xgetdate("1991-12-14T10:11Z", 0, 692705460);
	check_one_xgetdate("1991-12-14T10:11:12Z", 0, 692705472);
	check_one_xgetdate("1991-12-14T10:11:12?", EINVAL, 0);
	check_one_xgetdate("1991-12-14T03-07", 0, 692704800);
	check_one_xgetdate("1991-12-14T06:41-03:30", 0, 692705460);
	check_one_xgetdate("1991-12-14T03:11:12-07:00", 0, 692705472);
	check_one_xgetdate("19911214 031112-0700", 0, 692705472);;
}

#define TM_FORMAT "%04d-%02d-%02d %02d:%02d:%02d (%d/7, %d/365%s)"

#define TM_PRINTF(tm) \
	(1900 + (tm).tm_year), (tm).tm_mon, (tm).tm_mday, \
	(tm).tm_hour, (tm).tm_min, (tm).tm_sec, \
	((tm).tm_wday + 1), ((tm).tm_yday + 1), \
	((tm).tm_isdst ? ((tm).tm_isdst < 0 ? ", DST?" : ", DST") : "")

/** Check one xmktime() result. */
static bool check_one_xmktime(time_t expected) {
	struct tm tm;
	if (!localtime_r(&expected, &tm)) {
		bfs_ediag("localtime_r(%jd)", (intmax_t)expected);
		return false;
	}

	time_t actual;
	return bfs_echeck(xmktime(&tm, &actual) == 0, "xmktime(" TM_FORMAT ")", TM_PRINTF(tm))
		&& bfs_check(actual == expected, "xmktime(" TM_FORMAT "): %jd != %jd", TM_PRINTF(tm), (intmax_t)actual, (intmax_t)expected);
}

/** xmktime() tests. */
static void check_xmktime(void) {
	for (time_t time = -10; time <= 10; ++time) {
		check_one_xmktime(time);
	}

	// Attempt to trigger overflow (but don't test for it, since it's not mandatory)
	struct tm tm = {
		.tm_year = INT_MAX,
		.tm_mon = INT_MAX,
		.tm_mday = INT_MAX,
		.tm_hour = INT_MAX,
		.tm_min = INT_MAX,
		.tm_sec = INT_MAX,
		.tm_isdst = -1,
	};
	time_t time;
	xmktime(&tm, &time);
}

/** Check one xtimegm() result. */
static void check_one_xtimegm(const struct tm *tm) {
	struct tm tma = *tm, tmb = *tm;
	time_t ta, tb;
	ta = mktime(&tma);
	if (xtimegm(&tmb, &tb) != 0) {
		tb = -1;
	}

	bool pass = true;
	pass &= bfs_check(ta == tb, "%jd != %jd", (intmax_t)ta, (intmax_t)tb);
	if (ta != -1) {
		pass &= bfs_check(tm_equal(&tma, &tmb));
	}

	if (!pass) {
		bfs_diag("mktime():  " TM_FORMAT, TM_PRINTF(tma));
		bfs_diag("xtimegm(): " TM_FORMAT, TM_PRINTF(tmb));
		bfs_diag("(input):   " TM_FORMAT, TM_PRINTF(*tm));
	}
}

#if !BFS_HAS_TIMEGM
/** Check an overflowing xtimegm() call. */
static void check_xtimegm_overflow(const struct tm *tm) {
	struct tm copy = *tm;
	time_t time = 123;

	bool pass = true;
	pass &= bfs_check(xtimegm(&copy, &time) == -1 && errno == EOVERFLOW);
	pass &= bfs_check(tm_equal(&copy, tm));
	pass &= bfs_check(time == 123);

	if (!pass) {
		bfs_diag("xtimegm(): " TM_FORMAT, TM_PRINTF(copy));
		bfs_diag("(input):   " TM_FORMAT, TM_PRINTF(*tm));
	}
}
#endif

/** xtimegm() tests. */
static void check_xtimegm(void) {
	struct tm tm = {
		.tm_isdst = -1,
	};

#if BFS_HAS_TIMEGM
	// Check that xtimegm(-1) isn't an error
	for (time_t time = -10; time <= 10; ++time) {
		if (bfs_check(gmtime_r(&time, &tm), "gmtime_r(%jd)", (intmax_t)time)) {
			check_one_xtimegm(&tm);
		}
	}
#else
	// Check equivalence with mktime()
	for (tm.tm_year =  10; tm.tm_year <= 200; tm.tm_year += 10)
	for (tm.tm_mon  =  -3; tm.tm_mon  <=  15; tm.tm_mon  +=  3)
	for (tm.tm_mday = -31; tm.tm_mday <=  61; tm.tm_mday +=  4)
	for (tm.tm_hour =  -1; tm.tm_hour <=  24; tm.tm_hour +=  5)
	for (tm.tm_min  =  -1; tm.tm_min  <=  60; tm.tm_min  += 31)
	for (tm.tm_sec  = -60; tm.tm_sec  <= 120; tm.tm_sec  +=  5) {
		check_one_xtimegm(&tm);
	}

	// Check integer overflow cases
	check_xtimegm_overflow(&(struct tm) { .tm_sec = INT_MAX, .tm_min = INT_MAX });
	check_xtimegm_overflow(&(struct tm) { .tm_min = INT_MAX, .tm_hour = INT_MAX });
	check_xtimegm_overflow(&(struct tm) { .tm_hour = INT_MAX, .tm_mday = INT_MAX });
	check_xtimegm_overflow(&(struct tm) { .tm_mon = INT_MAX, .tm_year = INT_MAX });
#endif // !BFS_HAS_TIMEGM
}

void check_xtime(void) {
	check_xgetdate();
	check_xmktime();
	check_xtimegm();
}
