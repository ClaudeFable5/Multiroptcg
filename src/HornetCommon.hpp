#ifndef HORNETCOMMON_HPP
#define HORNETCOMMON_HPP
#include <array>
#define BOOST_USE_WINDOWS_H // NOTE: Workaround for Boost on Windows.
#include <boost/interprocess/sync/interprocess_condition.hpp>
#include <boost/interprocess/sync/interprocess_mutex.hpp>
#include <boost/interprocess/sync/scoped_lock.hpp>
#undef BOOST_USE_WINDOWS_H

namespace ipc = boost::interprocess;

namespace Ignis::Hornet
{

using LockType = ipc::scoped_lock<ipc::interprocess_mutex>;

enum class Action : uint8_t
{
	// Any function that calls DataReader also calls DataReaderDone.
	// Any function that calls ScriptReader can potentially call LogHandler.
	// ScriptReader can recurse to load nested scripts.
	NO_WORK = 0U, // Callbacks: doesn't apply
	HEARTBEAT, // Callbacks: doesn't apply
	EXIT, // Callbacks: doesn't apply
	EXIT_CONFIRMED, // Callbacks: doesn't apply
	OCG_GET_VERSION, // Callbacks: none
	OCG_CREATE_DUEL, // Callbacks: ScriptReader
	OCG_DESTROY_DUEL, // Callbacks: none
	OCG_DUEL_NEW_CARD, // Callbacks: DataReader, ScriptReader
	OCG_START_DUEL, // Callbacks: none
	OCG_DUEL_PROCESS, // Callbacks: DataReader, ScriptReader
	OCG_DUEL_GET_MESSAGE, // Callbacks: none
	OCG_DUEL_SET_RESPONSE, // Callbacks: none
	OCG_LOAD_SCRIPT, // Callbacks: ScriptReader
	OCG_DUEL_QUERY_COUNT, // Callbacks: none
	OCG_DUEL_QUERY, // Callbacks: none
	OCG_DUEL_QUERY_LOCATION, // Callbacks: none
	OCG_DUEL_QUERY_FIELD, // Callbacks: none
	CB_DATA_READER, // Callbacks: doesn't apply
	CB_SCRIPT_READER, // Callbacks: doesn't apply
	CB_LOG_HANDLER, // Callbacks: doesn't apply
	CB_DATA_READER_DONE, // Callbacks: doesn't apply
	CB_DONE, // Callbacks: doesn't apply
};

struct SharedSegment
{
	ipc::interprocess_mutex mtx;
	ipc::interprocess_condition cv;
	Action act{Action::NO_WORK};
	// [OPCG] 4MiB, up from u16max*2 (128KiB): CB_SCRIPT_READER copies whole
	// script files through here and opcg_card_meta.lua alone is ~340KiB —
	// the old capacity made the multirole-side memcpy write past the mapping
	// and kill the server on the FIRST duel creation of every OPCG room
	// (2026-07-13 crash dump: write AV at segment end, deterministic).
	// Multirole and hornet share this layout: rebuild BOTH in lockstep.
	std::array<uint8_t, 0x400000U> bytes{};
};

} // namespace Ignis::Hornet

#endif // HORNETCOMMON_HPP
