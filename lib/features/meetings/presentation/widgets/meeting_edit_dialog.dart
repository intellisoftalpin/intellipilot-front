import 'package:flutter/material.dart';
import 'package:intellipilot/core/datetime/timezones.dart';
import 'package:intellipilot/features/meetings/data/dtos/meeting_dtos.dart';
import 'package:intellipilot/features/meetings/presentation/meeting_format.dart';
import 'package:intellipilot/l10n/generated/app_localizations.dart';

/// What the meeting details dialog produced.
class MeetingFormValue {
  const MeetingFormValue({
    required this.title,
    required this.date,
    required this.timezone,
    this.startTime,
    this.endTime,
    this.location = '',
    this.description = '',
  });

  final String title;
  final DateTime date;
  final MeetingTime? startTime;
  final MeetingTime? endTime;
  final String timezone;
  final String location;
  final String description;

  CreateMeetingRequest toCreate() => CreateMeetingRequest(
    title: title,
    date: date,
    startTime: startTime,
    endTime: endTime,
    timezone: timezone,
    location: location,
    description: description,
  );

  /// Sends every field, so emptied ones are cleared on the server too.
  UpdateMeetingRequest toUpdate() => UpdateMeetingRequest(
    title: title,
    date: date,
    setTimes: true,
    startTime: startTime,
    endTime: endTime,
    timezone: timezone,
    location: location,
    description: description,
  );
}

/// Opens the create (when [initial] is null) or edit dialog.
Future<MeetingFormValue?> showMeetingEditDialog(
  BuildContext context, {
  required DateTime initialDate,
  required String defaultTimezone,
  Meeting? initial,
}) => showDialog<MeetingFormValue>(
  context: context,
  builder: (_) => MeetingEditDialog(
    initialDate: initialDate,
    defaultTimezone: defaultTimezone,
    initial: initial,
  ),
);

class MeetingEditDialog extends StatefulWidget {
  const MeetingEditDialog({
    required this.initialDate,
    required this.defaultTimezone,
    this.initial,
    super.key,
  });

  final DateTime initialDate;
  final String defaultTimezone;
  final Meeting? initial;

  @override
  State<MeetingEditDialog> createState() => _MeetingEditDialogState();
}

class _MeetingEditDialogState extends State<MeetingEditDialog> {
  late final TextEditingController _title;
  late final TextEditingController _location;
  late final TextEditingController _description;
  late DateTime? _date;
  MeetingTime? _start;
  MeetingTime? _end;
  late String _timezone;
  MeetingFormError? _error;

  @override
  void initState() {
    super.initState();
    final m = widget.initial;
    _title = TextEditingController(text: m?.title ?? '');
    _location = TextEditingController(text: m?.location ?? '');
    _description = TextEditingController(text: m?.description ?? '');
    _date = m?.date ?? widget.initialDate;
    _start = m?.startTime;
    _end = m?.endTime;
    _timezone = m?.timezone ?? widget.defaultTimezone;
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 20),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<MeetingTime?> _pickTime(
    MeetingTime? current,
    MeetingTime fallback,
  ) async {
    final initial = current ?? fallback;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
    );
    return picked == null ? null : MeetingTime(picked.hour, picked.minute);
  }

  void _submit() {
    final error = validateMeetingForm(
      title: _title.text,
      date: _date,
      start: _start,
      end: _end,
    );
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(
      MeetingFormValue(
        title: _title.text.trim(),
        date: _date!,
        startTime: _start,
        endTime: _start == null ? null : _end,
        timezone: _timezone,
        location: _location.text.trim(),
        description: _description.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final ml = MaterialLocalizations.of(context);
    final zones = {...kTimezones, _timezone}.toList();
    return AlertDialog(
      title: Text(
        widget.initial == null ? t.meetingCreateTitle : t.meetingEditTitle,
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('meeting-title'),
                controller: _title,
                autofocus: widget.initial == null,
                maxLength: 300,
                decoration: InputDecoration(labelText: t.meetingFieldTitle),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 8),
              _PickerField(
                key: const Key('meeting-date'),
                label: t.meetingFieldDate,
                value: _date == null ? null : ml.formatMediumDate(_date!),
                icon: Icons.event_outlined,
                onTap: _pickDate,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _PickerField(
                      key: const Key('meeting-start'),
                      label: t.meetingFieldStart,
                      value: _start?.wire,
                      icon: Icons.schedule_outlined,
                      onTap: () async {
                        final v = await _pickTime(
                          _start,
                          const MeetingTime(9, 0),
                        );
                        if (v != null) setState(() => _start = v);
                      },
                      onClear: _start == null
                          ? null
                          : () => setState(() {
                              _start = null;
                              _end = null;
                            }),
                      clearTooltip: t.meetingClearTime,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PickerField(
                      key: const Key('meeting-end'),
                      label: t.meetingFieldEnd,
                      value: _end?.wire,
                      icon: Icons.schedule_outlined,
                      onTap: () async {
                        final s = _start;
                        final v = await _pickTime(
                          _end,
                          s == null
                              ? const MeetingTime(10, 0)
                              : MeetingTime(
                                  (s.hour + 1).clamp(0, 23),
                                  s.minute,
                                ),
                        );
                        if (v != null) setState(() => _end = v);
                      },
                      onClear: _end == null
                          ? null
                          : () => setState(() => _end = null),
                      clearTooltip: t.meetingClearTime,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownMenu<String>(
                initialSelection: _timezone,
                label: Text(t.meetingFieldTimezone),
                expandedInsets: EdgeInsets.zero,
                enableFilter: true,
                requestFocusOnTap: true,
                menuHeight: 320,
                dropdownMenuEntries: [
                  for (final tz in zones)
                    DropdownMenuEntry<String>(value: tz, label: tz),
                ],
                onSelected: (v) {
                  if (v != null) setState(() => _timezone = v);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _location,
                maxLength: 2000,
                decoration: InputDecoration(
                  labelText: t.meetingFieldLocation,
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _description,
                minLines: 3,
                maxLines: 8,
                decoration: InputDecoration(
                  labelText: t.meetingFieldDescription,
                  alignLabelWithHint: true,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  meetingFormErrorText(t, _error!),
                  key: const Key('meeting-form-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.actionCancel),
        ),
        FilledButton(
          key: const Key('meeting-submit'),
          onPressed: _submit,
          child: Text(widget.initial == null ? t.actionCreate : t.actionSave),
        ),
      ],
    );
  }
}

/// A read-only field that opens a picker, with an optional clear button.
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.onClear,
    this.clearTooltip,
    super.key,
  });

  final String label;
  final String? value;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final String? clearTooltip;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: onClear == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: clearTooltip,
                  onPressed: onClear,
                ),
        ),
        isEmpty: value == null,
        child: Text(value ?? ''),
      ),
    );
  }
}
