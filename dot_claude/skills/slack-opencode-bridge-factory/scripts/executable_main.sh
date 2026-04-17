#!/usr/bin/env bash
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
	cat <<EOF
Usage: omo-bridge <command> [options]

Commands:
  create   --name <agent> [--project P] [--role R] [--model M]   Create new agent bridge (Phase 1)
  finalize <agent> --bot-token T --app-token T                    Complete setup (Phase 2)
  list     [--json] [--name N]                                    List registered agents
  restart  <agent> [--only opencode|bridge]                       Restart agent daemons
  logs     <agent> [--tail N] [--follow] [--only opencode|bridge] Show agent logs
  update   <agent> [--model M] [--role-file P] [--rotate-tokens]  Update agent config
  delete   <agent> [--force] [--purge-project] [--purge-logs]     Remove agent
  migrate  <agent> [--dry-run]                                    Migrate legacy agent to V1/V2

Options:
  --help, -h   Show this help message

Examples:
  omo-bridge create --name cpo --project ~/projects/cpo --role "CPO agent"
  omo-bridge finalize cpo --bot-token xoxb-... --app-token xapp-...
  omo-bridge list
  omo-bridge restart secretary
  omo-bridge logs secretary --tail 20 --only bridge
  omo-bridge delete cpo --force
EOF
}

case "${1:-}" in
create)
	shift
	exec bash "$SKILL_DIR/scripts/create.sh" "${@}"
	;;
finalize)
	exec bash "$SKILL_DIR/scripts/create.sh" "${@}"
	;;
list)
	shift
	exec bash "$SKILL_DIR/scripts/list.sh" "${@}"
	;;
restart)
	shift
	exec bash "$SKILL_DIR/scripts/restart.sh" "${@}"
	;;
logs)
	shift
	exec bash "$SKILL_DIR/scripts/logs.sh" "${@}"
	;;
update)
	shift
	exec bash "$SKILL_DIR/scripts/update.sh" "${@}"
	;;
delete)
	shift
	exec bash "$SKILL_DIR/scripts/delete.sh" "${@}"
	;;
migrate)
	shift
	exec bash "$SKILL_DIR/scripts/migrate.sh" "${@}"
	;;
--help | -h | help) usage ;;
"")
	usage
	exit 1
	;;
*)
	echo "ERROR: Unknown command: $1" >&2
	echo ""
	usage >&2
	exit 1
	;;
esac
