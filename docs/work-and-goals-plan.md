# Work and goals plan

Date: 2026-09-09

Status: Stages 1-4 implemented, with the platform limitations below. Stage 5
(complete integration) remains. This is not yet the complete Work release.

## 1. Confirmed product decisions

The following decisions were selected during planning:

| Decision | Agreed direction |
| --- | --- |
| Work and To-dos | Keep To-dos for quick personal items. Add Work separately, with an explicit Move to Work action. |
| Goals | Include lightweight, optional goals in the first complete release. Do not require an OKR setup. |
| Task nesting | Initially expose tasks and one level of full-featured subtasks. Keep storage suitable for deeper nesting later. |
| Personal goals | Include standalone personal goals with optional habit connections editable from either side. |
| Goals navigation | Use one shared Goals hub with Personal and Work views, accessed from Today and Work rather than another main-navigation destination. |

The remaining details are the recommended design, not additional confirmed
implementation decisions.

### Stage 1 implementation notes

- New records use shared IDs, UTC metadata timestamps, a persisted logical
  creation day, revisions, archive markers, and deletion markers. Date-only
  fields use the app's existing `dd-MM-yyyy` keys.
- `WorkData` holds an immutable, validated graph of work areas, projects, tasks,
  shared goals, habit links, notes/activity, and planned work blocks.
- `LocalStore.updateWork` serializes graph mutations. `writeWork` additionally
  requires the caller's expected graph revision to reject stale edits.
- Shared goals support manual measurements, Work delivery roll-ups, and measured
  habit contributions. Links capture source settings; incompatible changes,
  missing sources, mixed metrics, and duplicate contributors fail explicitly
  rather than manufacturing progress.
- The first storage implementation journals a complete graph snapshot in a
  dedicated Hive box before publishing it. Startup replays interrupted writes.
  Its atomic boundary is the new graph, not the existing habit, To-do, or focus
  collections. Cross-domain conversion/session operations belong to later stages.
- Backup format 2 contains the versioned Work/Goals graph. Replacing from a legacy
  backup without that graph preserves existing Work and Goals data.
- Readable backups include Work and Goals documents without claiming existing
  user-authored files. Photo retention includes archived/deleted Work references.
- Folder merging accepts disjoint or identical records and refuses conflicting
  edits. Rejected or unsupported snapshots are retained locally and retried
  before newer files; automatic publication is paused for that folder.
- Interactive conflict resolution and portable binary attachment packaging remain
  stage 5 work. A supported conflicting snapshot can be selected through the
  existing backup restore flow, then the folder can be refreshed again.

### Stage 2 implementation notes

- Work is available in Classic/Express navigation and desktop rails. Minimal
  mobile uses a labeled page switcher. Its visibility preference preserves data.
- Work areas, projects, tasks and subtasks have creation/editing flows, detail
  pages, search, status/priority/date filters, notes/photos, and archive/restore.
- Parent completion is explicit. Project/task roll-ups count leaf work once,
  including archived work rather than inflating progress by hiding it.
- Tasks can be moved or duplicated. Inbox, standalone-area, project and subtask
  lists support accessible manual sibling ordering.
- Move to Work uses a recoverable journal, retains source details and photo
  references, and updates To-do reminders/widgets. Stale widget actions cannot
  recreate a moved To-do.
- Classic, Minimal and Express share the same behavior, with keyboard-accessible
  controls, narrow/large-text layouts, and existing theme tokens.

### Stage 3 implementation notes

- Work tasks and subtasks use the existing focus engine, including timed,
  open-ended, and Pomodoro sessions. Only one session can run at a time; Cancel
  in the switching dialog leaves the current session intact.
- Typed focus targets retain task/project/work-area snapshots. Active spans
  exclude pauses and breaks and allocate Work time across reporting days.
- Stable session/phase identities and a persisted transition journal support
  recovery and idempotent phase saves. Native actions are acknowledged after
  persistence, and stale phase actions are rejected.
- Saving a session is separate from completing its task. Session notes and
  explicit completion are saved through the finish dialog. Restarting a Work
  phase offers to save the recorded time first.
- Task, project, and area details show time history with direct/subtask and
  focused/manual breakdowns. Manual entries and corrections validate duration,
  future dates, overlap, target context, and record revisions.
- Work time is included in overall focus reporting, with All/Habits/Work
  filters. It does not generate habit completions, streaks, or Island rewards.
- Planned blocks are editable from task details and appear chronologically with
  habits in the day timeline. Overlaps are disclosed without moving deadlines.
  Work opens the calendar day; habit entry points preserve the logical-day
  setting.
- Reminders are explicit timestamps, separate from deadlines and planned blocks.
  Permission requests occur on intentional reminder setup, not every refresh.
  Scheduling is refreshed when Work changes; closed or archived contexts stop
  receiving reminders. Snoozes are retained across refreshes.
- Backup format 3 includes typed time records, notes, spans, and deletion
  markers. Legacy replacements preserve Work time; conflicting or overlapping
  Work time imports require a choice instead of silently overwriting records.

### Stage 4 implementation notes

- One shared Goals hub serves Personal and Work views. Today and Work open the
  same hub; there is no additional main-navigation destination. Pinned personal
  goals appear on Today, and Work goals can be filtered by work area and
  project.
- Goal cards, details, forms, history, and the connection editor use the Work
  design system in all three styles, both appearances, at 320 px widths and
  2x text, with keyboard navigation.
- Measurements are completion, percentage, number (with unit), or currency.
  Sources are manual updates, habit contributions, or Work delivery. Achievement
  requires an explicit action; reaching the target never changes status on its
  own, and Work delivery is always read from the current task graph rather than
  a cached value.
- Habit connections are editable from the goal and from the habit. Supporting
  connections never change measured progress. Measured contributions require a
  habits-sourced goal with a matching metric and unit and an explicit start
  date; the editor previews the recalculated value before saving. Habit undo and
  backfill recompute goal progress; goal changes never write habit completions,
  streaks, or Island rewards. Missing or changed habit sources are reported as
  setup states instead of silent zeros.
- A habit can be created from a goal and a goal from a habit. If the habit saves
  but its connections do not, the form keeps the saved habit, explains the
  partial save, and a retry updates the same habit instead of creating another.
- Goal history records manual updates, status and configuration changes, and
  connection changes, stamped with the measurement unit, kind, source, baseline,
  and target at that time. Backdated updates keep their date and only change
  the current value when they are the latest entry. Notes support photos.
- Work insights summarise focused and manual time, leaf-task delivery, open,
  blocked, and overdue work, and time per project using the project recorded at
  the time of the session. Parent and subtask completions are not double
  counted; cancelled, archived, and completed contexts are excluded; windows are
  capped at one year; duplicate time records are rejected.
- Backups retain goal pins, ordering, measurement snapshots, and removed-link
  markers, and the readable export includes goal history with its units.
- Reminder scheduling failures no longer block habit saves: if the notification
  service cannot initialise, the habit and its goal connections are still saved
  and the failure is logged.

### Platform limitations

- Scheduled Work reminders are unsupported by the current Windows notification
  implementation. The app retains the reminder configuration and displays the
  limitation instead of claiming delivery. Task focus, time history, and
  planning remain available on Windows.
- At most the next 64 Work notifications are scheduled at once; the app displays
  a notice when more are pending and refreshes the queue when reopened.
- Android notification bridge changes are included, but an Android package
  could not be built in this environment because the Android SDK is absent.
  Device-level background notification delivery remains to be exercised with
  the native toolchain.

## 2. Product principles

Work should connect planning, execution, and focused effort without turning
Streak into an enterprise project-management application.

- Keep companies, projects, goals, and habit connections optional where possible.
- Make quick capture possible with only a title or name.
- Separate delivery progress, outcome progress, and time invested.
- Reuse the existing focus engine and design system.
- Preserve existing habits, To-dos, statistics, and their intended behavior.
- Keep the initial release solo-first, local, and offline.
- Avoid rewarding long hours or uninterrupted streaks as a proxy for productivity.

Projects describe what is being delivered. Goals describe why it matters. Tasks
describe the next actions. Focus sessions record the effort invested.

Teamflect is inspiration for connecting goals to execution and offering different
measurements, not for importing departments, approvals, performance reviews, or a
mandatory organization chart.

## 3. Information architecture

### Work hierarchy

```text
Work
  Company / work area
    Project
      Task
        Subtask
  Work inbox
```

Intermediate containers are optional. A task can remain in the Work inbox, belong
directly to a work area, or belong to a project. A project does not require a
company selection.

| Concept | Purpose | Example |
| --- | --- | --- |
| Company / work area | Separate jobs, clients, or independent work | Acme, Freelance, My business |
| Project | Group work toward a deliverable | Website redesign |
| Task | Represent a meaningful piece of work | Build the onboarding flow |
| Subtask | Represent an independently actionable part of a task | Implement the welcome screen |
| Work inbox | Capture work before organizing it | Investigate the login issue |
| Goal | Describe an outcome supported by work or habits | Reduce onboarding abandonment |

Subtasks inherit their parent and project/work-area context. They have their own
status, dates, estimates, notes, and focus history. Parent dates or estimates must
not silently overwrite independently edited subtask values.

### Shared goals

Goals are a separate feature with Personal and Work scopes.

A personal goal can stand alone without a habit, project, or company. A Work goal
can be associated with a company/work area or project. Goals sit alongside the
work hierarchy, rather than becoming a required level inside it.

Habits can connect to goals in either scope. Goal connections are optional and do
not change a habit's fundamental tracking behavior.

## 4. Navigation and screens

### App navigation

Add Work to the existing destinations:

```text
Today | To-dos | Work | Stats | Settings
```

Work should be independently hideable, like the existing optional To-dos
feature. Hiding it must not delete its data.

Classic and Express can extend the existing navigation shell. Minimal mobile
needs a clearly labeled Work entry or page switcher rather than another icon
squeezed into its compact header.

The shared Goals hub is accessible from Today and Work. Entering from Work
selects the Work view; Today provides access to personal goals and optionally
shows a compact set of pinned goals.

### Work navigation

Keep the main Work navigation small:

```text
Overview | Projects | Goals
```

Provide an Inbox shortcut and access to Work insights without creating another
large navigation bar. A work-area selector defaults to All work and consistently
filters the relevant views.

| Screen | Main content and actions |
| --- | --- |
| Overview | Continue the active session, today's planned work, due and overdue items, blocked tasks, and a compact weekly focus summary |
| Work inbox | Quick capture, unfiled tasks, and actions to assign a work area or project |
| Company / work area | Its projects, standalone tasks, goals, reference details, and recent activity |
| Projects | Searchable projects with status, deadline, delivery progress, and time spent |
| Project detail | Description, task/subtask list, linked goals, notes, and project activity |
| Task detail | Status, description, scheduling, subtasks, progress, focus history, and notes |
| Goals hub | Personal and Work views using shared goal cards, forms, and behavior |
| Goal detail | Measurement, target, progress history, supporting habits/work, deadline, and updates |
| Work insights | Time allocation, completed work, overdue work, and goal trends |

### Responsive behavior

On desktop, reuse the existing navigation rail and list/detail pane. Selecting a
task should open its details without losing the working list.

On mobile, use full-page details and compact creation sheets. Avoid deeply
indented, horizontally scrolling task trees.

## 5. Forms and input fields

### Quick creation

A name or title should be the only required typed input for ordinary creation.
Inherit context from the location where Add was selected.

Measurement-specific fields become required only when that measurement is
selected. For example, a numeric goal needs a meaningful target and unit.

Put dates, estimates, connections, and customization into clearly labeled
optional sections.

### Work records

| Entity | Main fields | Optional details |
| --- | --- | --- |
| Company / work area | Name; type such as Company, Client, or Independent | Description, role, icon/color, cover image, reference links, working days, weekly focus target |
| Project | Name; work area; status | Description, intended outcome, start date, deadline, priority, tags, related goal, notes, links, cover |
| Task | Title; project/work area; status | Description and completion criteria, priority, due date/time, planned work blocks, effort estimate, reminders, tags, focus defaults |
| Subtask | Same task fields, with an inherited parent and context | Its own priority, deadline, estimate, notes, progress, and focus sessions |

Subtasks must be real task records, not reused habit `Substep` records. Existing
habit substeps are simple checklist steps whose completion belongs to a
particular day; work subtasks need persistent state and their own history.

### Task detail grouping

| Group | Contents |
| --- | --- |
| Details | Description, expected result, reference links |
| Planning | Planned date/time blocks, due date, priority, estimated effort |
| Progress | Completion mode, current progress, subtasks |
| Focus | Start focus, session duration/break defaults, tracked time |
| Notes and activity | Notes, photos, session summaries, status and progress changes |

Planned time means when work is intended to happen. Due time means when it needs
to be finished. Moving a work block must not silently move its deadline.

Initially support notes, links, and photos using existing patterns. Arbitrary
document attachments can follow once their storage and portability are supported.

### Shared goal fields

| Group | Fields |
| --- | --- |
| Basics | Title, description, Personal/Work scope, optional category, icon/color |
| Purpose | Optional Why this matters note |
| Measurement | Completion, percentage, number, currency, or a measurement supplied by linked activity |
| Target | Baseline, target value, unit/currency where applicable |
| Timing | Start date, optional target date |
| Connections | Supporting habits/work and explicitly configured contributors |
| History | Progress updates, notes, and changes to targets or connections |

Personal categories can include Learning, Health, Finances, Creative, or a custom
category. They organize goals without adding another required hierarchy.

## 6. Status and delivery progress

### Statuses

| Entity | Suggested statuses |
| --- | --- |
| Task / subtask | Not started, In progress, Blocked, Done, Cancelled |
| Project | Planned, Active, On hold, Done, Cancelled |
| Goal | Not started, Active, Paused, Achieved, Cancelled |

Archive is separate from completion or cancellation.

Overdue is derived from a deadline, not another status. Blocked can have an
optional reason.

Projects and goals can optionally expose an On track / At risk / Off track
assessment. Do not infer that something is on track merely from elapsed time.

### Three separate measurements

| Measurement | Question answered |
| --- | --- |
| Delivery progress | How much of the planned work is complete? |
| Outcome progress | How close are we to the goal? |
| Time invested | How much work time has been recorded? |

A completed focus timer does not mean a completed task. Completed tasks do not
automatically prove a revenue, customer, or other independently measured outcome.

### Calculation and completion rules

1. Leaf tasks use completion-based progress by default, with optional manual percentage tracking for longer work.
2. A task with subtasks derives progress from them rather than exposing a competing manual percentage.
3. Projects aggregate leaf work items once, not parent tasks plus their children.
4. Use equal weighting initially. Explicit weighting can follow; priority or changing time estimates should not silently become progress weights.
5. Completing a parent must not silently finish its open children. Offer an explicit action to finish remaining subtasks or cancel the operation.
6. Empty containers show No tasks yet, not a misleading 100%.
7. Cancelling work can remove it from delivery scope, with an activity entry. Archiving alone must not manufacture progress.
8. Reaching the end of a progress bar and explicitly closing a task/project are separate concepts.

A company/work area is an ongoing context, not something that becomes 100%
complete. Its overview should emphasize active projects, goals, due work, and
time allocation instead of an unexplained company-wide percentage.

## 7. Goal measurements and habit connections

### Goal measurements

Include completion, percentage, number with a unit, and currency with an explicit
currency code. Linked work can supply delivery progress. Linked habit activity
can supply suitable quantities, durations, completed days, or consistency.

Numeric measurements need a baseline and target so decreasing goals also work,
such as reducing unresolved issues. Preserve raw values even when a progress bar
reaches 100%.

Never add incompatible units or currencies. Prevent a work roll-up from counting
both a project and its already-included tasks as duplicate contributors.

### Linking from either direction

| Starting point | Actions |
| --- | --- |
| Goal detail | Link an existing habit, create a habit for this goal, inspect contributions |
| Habit detail | Link an existing goal, create a goal from this habit, see related goals |
| Habit creation/editing | Optional Related goals field |
| Goal creation/editing | Optional Supporting habits section |

Support many-to-many relationships: one goal can involve several habits, and one
habit can support several goals.

Store one canonical relationship visible from both sides, not two independent
lists. Bidirectional linking means the relationship can be viewed and edited
from either side; it does not mean goal completion fabricates habit completions.

### Supporting versus contributing

| Link mode | Behavior |
| --- | --- |
| Supporting habit | Show the connection and habit activity without changing measured goal progress |
| Measured contributor | Update goal progress using an explicitly selected habit measurement |

Linking alone should default to supporting. Automatic contribution is an
explicit option with a preview of what will count.

For example, completing a budget-review habit supports a savings goal but does
not prove that money was saved. Practice hours can support a performance
milestone without automatically completing it.

Each goal has one primary measurement source. Other connected habits or work
items can remain supportive.

### Personal goal examples

| Goal | Connection |
| --- | --- |
| Read 3,000 pages this year | Accumulate pages from a reading habit |
| Exercise on 100 days this year | Count completed days from an exercise habit |
| Practice Spanish for 40 hours | Accumulate duration from a practice habit |
| Save a chosen amount | Record savings manually and link budget review as support |
| Finish a personal milestone | Track completion manually with optional supporting habits |

### Initial automatic habit measurements

- Completed days, for goals such as exercising on 100 days.
- Accumulated quantity, such as pages or another compatible unit.
- Accumulated duration, such as practice or study time.
- Schedule-based consistency over a defined period.

Consistency must respect daily, weekly, monthly, and interval schedules rather
than assuming every habit must happen every day. Rest days and vacations need
appropriate treatment.

A measured link needs its measurement, counting date range, unit compatibility,
and a choice about including existing activity within the range. Preview the
result before saving so linking an older habit does not unexpectedly complete a
new goal.

### Contribution safeguards

Habit records remain authoritative. Derive goal progress from eligible activity
instead of blindly incrementing a goal whenever a button is tapped.

- Undoing or correcting a habit entry updates affected active goals.
- Backdated entries contribute only within the configured date range.
- Reloads and imports must not count the same activity again.
- A time goal uses habit-recorded time or focus-session time, not both when focus already fills that habit.
- Changing a habit's unit or schedule must not silently reinterpret earlier contributions.
- Unlinking previews its effect on progress and preserves the update history.
- Archiving/deleting a goal never deletes its habits.
- Achieving a goal does not automatically stop its habits.

A habit may intentionally contribute to several goals, but app-wide activity
totals still count the underlying activity only once.

### Goal and habit detail presentation

Goal detail presents the outcome first, followed by supporting habits and work.
For manually measured outcomes, show supporting consistency separately rather
than blending it into the outcome progress bar.

Habit detail gains a Related goals section showing each connection and its role.
Habits remain fully usable without any goal connection.

Starting focus from a goal offers its linked habits or tasks. The timer still
attaches to one concrete habit or task.

## 8. Task-specific focus and time history

### Reuse the existing engine

Extend the current focus engine rather than building another timer. Reuse timed
sessions, Pomodoro, open-ended focus, sounds, scenes, history, and recovery.

Introduce typed targets for a free session, habit, or work task. A subtask uses
the same work-task target model.

### Focus flow

1. Select Start focus on a task or subtask.
2. Show its company/work area, project, task, and selected subtask context.
3. Use the existing timer modes and appearance settings.
4. Keep relevant subtasks and session notes accessible during focus.
5. Save recorded time when the session finishes.
6. Optionally update progress, mark the item done, and write a next step.
7. Return to the task with updated history and totals.

Save session and Mark task done remain separate actions.

### Session rules

- Only one active session across Habits and Work.
- Starting another target offers Resume current session, Finish and switch, or Cancel.
- Switching targets must not retroactively assign earlier time to the new task.
- Pauses and breaks do not count as focused work.
- Retain short or interrupted Work effort without changing existing habit-specific logging behavior.
- Starting focus can move a not-started task to In progress; blocked or completed tasks require an explicit decision.
- Keep a running session discoverable while navigating elsewhere.

Allow focusing on a parent task even when it has subtasks. Label it as direct
work on the parent, distinct from time on its children. Aggregate each session
only once.

### Time records and reporting

Provide manual time entry and corrections for work completed outside the timer.
Distinguish manual entries from timed sessions and prevent duplicate or
overlapping accounting.

Work sessions contribute to overall focus totals, with All / Habits / Work
filters. They must not automatically increment habit completions, habit streaks,
or habit rewards.

Historical reports retain company/project attribution from when work happened.
Moving a task later must not silently rewrite earlier time allocation. Task
history can still show all time recorded against that task.

## 9. Planning, everyday operations, and habit feature reuse

### Daily planning

Represent task work blocks separately from deadlines. Support reviewing planned
work alongside relevant habits without changing habit scheduling semantics.

The Work overview should not duplicate the entire habit home screen. An optional
compact Work summary on Today is sufficient.

### Everyday operations

Include search, sorting, filtering, duplication, reordering, moving,
archiving/restoring, and completing/reopening work.

Filters include company/work area, project, status, priority, tag, due date, and
planned date. Search results for subtasks include enough parent context to
identify them.

### Reuse with adapted meaning

| Existing capability | Work or goal adaptation |
| --- | --- |
| One-tap logging | Quick completion and progress updates |
| Quantitative tracking | Goal measurements with units and history |
| Checklists | Full-featured work subtasks rather than daily-reset steps |
| Day planning | Task work blocks separate from deadlines |
| Reminders | Task reminders, snooze, and direct navigation |
| Notes and photos | Work notes and session outcomes |
| Activity grids and charts | Focus time, completed work, and goal trends |
| Categories and appearance | Work-area/project organization and personal goal categories |
| Archive | Hide inactive records without losing history |
| Backup and readable copies | Preserve Work, shared goals, links, and history |

Do not directly copy avoidance habits, relapses, daily resets, or perfect-day
pressure into work management.

An optional work-consistency view should respect working days and time off.
Weekends should not become failures.

## 10. Moving a To-do into Work

This is an explicit conversion, not an ongoing duplicate.

```text
To-do menu -> Move to Work -> Choose destination or Work inbox
```

Preserve the title/description, due date/time, priority, photos, creation
timestamp, and completion timestamp.

Remove the original To-do only after the Work record is durably saved.
Interrupted or repeated operations must not produce duplicates or lose data.

Transfer reminder responsibility, refresh the To-dos widget, and retain photo
references so cleanup cannot delete images still used by Work.

Personal To-dos otherwise remain unchanged.

## 11. Design system and accessibility

Support Classic, Minimal, and Express through shared behavior and style-aware
components, not three copies of the business logic.

Reuse the following foundations:

- `AppTheme`, `ColorScheme`, and `AppTokens`.
- Existing Minimal and Express typography, surfaces, buttons, and navigation.
- Lucide icons.
- Existing text fields, sheets, confirmation dialogs, empty states, and photo components.
- Existing responsive list/detail navigation.

Keep list rows focused on title, status, deadline, and a compact progress/time
summary. Put secondary metadata in details instead of dense tables everywhere.

Actions need keyboard access on Windows and appropriate Flutter semantics.
Status must not rely on color alone. Support larger text and RTL layouts, and
provide menu/button alternatives to dragging.

All user-facing strings belong in the existing English ARB localization source
and are accessed through the existing localization helpers.

## 12. Engineering architecture

### Feature boundaries

Create `lib\features\work\` and `lib\features\goals\`, following the existing
`data`, `state`, `pages`, and `widgets` organization.

Keep Flutter, Provider, and Hive CE. Goals are shared infrastructure referenced
by Work and Habits, not a Work-only model duplicated for personal use.

| Record or component | Responsibility |
| --- | --- |
| `WorkArea` | Company/client/independent-work context |
| `WorkProject` | Project details and lifecycle |
| `WorkTask` | Tasks and subtasks, using an optional `parentTaskId` |
| `Goal` | Shared Personal/Work goal with optional work context |
| `GoalHabitLink` | Canonical habit relationship, role, measurement, and date range |
| Work notes/activity | Notes, progress updates, and meaningful changes |
| Work plan blocks | Scheduled work against a task |
| Shared goal progress calculation | Derive progress from the selected authoritative source |
| Typed focus target | Identify free sessions, habits, and work tasks without a second timer |

Use stable IDs and versioned serialization. Keep the task model suitable for
deeper nesting while enforcing the initial one-subtask-level limit in domain
rules and the interface.

### Existing integration points

| Area | Required integration |
| --- | --- |
| App shell and settings | Work navigation, Goals entry points, visibility, controller registration, reload behavior |
| Habit forms and detail | Optional goal selection, related goals, creation/linking from either side |
| Focus controller/session/history | Typed targets, target-specific completion behavior, Work filters |
| Android focus service | Preserve Work identity through notification actions and recovery |
| Day planner | Extend its habit-specific model to represent task blocks |
| Notifications | Work reminders and routes without treating tasks as habits |
| Local storage | Work/goals/links and recoverable multi-record operations |
| Backup, restore, readable vault | Preserve hierarchy, measurements, contributions, sessions, notes, and photos |
| Image cleanup | Recognize retained Work/goal photo references, including archived/deleted records |

### Data safeguards

Backups include Work and shared goals from the beginning. An older backup without
those collections must not silently erase newer records.

Moves, parent changes, and session-plus-progress saves need recoverable
operations. Do not treat writes across separate Hive boxes as an automatic
multi-record transaction.

Deletion should be recoverable and disclose its descendant/history impact.
Renaming or deleting a target must not make historical focus sessions disappear
or become unidentifiable.

### Folder sync

The existing folder sync is basic backup-based merging, not collaborative
synchronization.

Work and goals need record revisions, deletion markers, and explicit handling of
conflicting edits. Taking the highest progress value is not a valid general
merge rule: tasks can be reopened and measurements can decrease.

Preserve link integrity and surface missing or conflicting source data instead
of silently substituting success-shaped values.

### Dates and time

Preserve date-only deadlines as dates and timed reminders as properly defined
instants. Moving planned work does not move deadlines.

Focus reporting must account for pauses and reporting-day boundaries without
changing existing habit history or double-counting time.

## 13. Delivery stages

These stages describe implementation order, not separate promises of complete
releases.

| Stage | Deliverable |
| --- | --- |
| 1. Domain and persistence (implemented) | Work records, shared goals and links, hierarchy rules, progress calculations, versioned storage/backup support, recoverable operations |
| 2. Core Work experience (implemented) | Navigation, inbox, companies, projects, task/subtask forms, search/filtering, notes, archive, Move to Work |
| 3. Focus and planning (implemented) | Task-specific focus, recovery and native actions, time history, manual time, work blocks, reminders; platform limits noted above |
| 4. Goals and insights (implemented) | Personal and Work goal views, bidirectional habit linking, measured contributions, linked work progress, update history, reports and filters |
| 5. Complete integration | All three styles, desktop/mobile behavior, portable data handling, folder-sync conflicts, deletion and restoration flows |

The first complete release includes all five stages. The shared goal/link
foundation belongs in stage 1; personal goals, Work goals, and habit linking ship
together in stage 4.

A useful internal milestone after stage 3 is the complete workflow:

```text
Create company -> Create project -> Add task/subtask -> Plan work
-> Focus -> Record progress -> Review history
```

## 14. Deliberately deferred scope

| Later feature | Reason to defer |
| --- | --- |
| Recurring task templates | Each occurrence needs separate completion/history rather than resetting the same task like a habit |
| Dependency graphs | Add real relationships and cycle handling after the basic hierarchy is stable |
| Kanban and richer calendar views | Alternative views should build on reliable task data |
| Project/task templates and saved views | More valuable after common workflows are established |
| Custom fields and advanced weighting | Avoid unnecessary configuration in the solo-first release |
| Full cascading OKRs | Keep initial goals lightweight and optional |
| Arbitrary document attachments | Require reliable storage, lifecycle, and portability |
| Billing, invoices, external integrations | Separate product scope |
| Collaboration | Requires explicit workspace, identity, permissions, and synchronization design |

Future collaboration should remain possible through stable identities and clean
scope boundaries. It must not introduce accounts, assignees, approval flows, or a
backend into this release. Those would be a separate departure from Streak's
current offline-first scope.

## References

- [Teamflect: Managing Goal Progress Types](https://help.teamflect.com/en/articles/8875975-managing-goal-progress-types-in-teamflect)
- [Teamflect: How Many Levels of Subgoals Can We Have?](https://help.teamflect.com/en/articles/8876162-how-many-levels-of-subgoals-can-we-have)
- Repository architecture and conventions: `CONTRIBUTING.md`.
