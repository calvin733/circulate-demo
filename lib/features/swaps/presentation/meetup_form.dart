import 'package:flutter/material.dart';

import '../../../core/widgets/shared_widgets.dart';

typedef MeetupInput = ({String location, DateTime scheduledAt});

Future<MeetupInput?> showMeetupForm(BuildContext context) =>
    showModalBottomSheet<MeetupInput>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _MeetupForm(),
    );

class _MeetupForm extends StatefulWidget {
  const _MeetupForm();
  @override
  State<_MeetupForm> createState() => _MeetupFormState();
}

class _MeetupFormState extends State<_MeetupForm> {
  final _form = GlobalKey<FormState>();
  final _location = TextEditingController();
  DateTime? _time;
  String? _error;
  @override
  void dispose() {
    _location.dispose();
    super.dispose();
  }

  Future<void> _select() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
      initialDate: _time ?? now.add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_time ?? now),
    );
    if (time != null && mounted) {
      setState(() {
        _time = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        );
        _error = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Usulkan pertemuan',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            const Text(
              'Pilih tempat publik. Usulan baru memerlukan persetujuan pihak lain. Batas waktu adalah 30 hari sejak penawaran diterima.',
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _location,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Tempat publik dan titik bertemu',
              ),
              validator: (v) => (v ?? '').trim().length < 5
                  ? 'Jelaskan tempat dengan setidaknya 5 karakter.'
                  : null,
            ),
            OutlinedButton.icon(
              onPressed: _select,
              icon: const Icon(Icons.event_outlined),
              label: Text(
                _time == null ? 'Pilih tanggal dan jam' : displayDate(_time!),
              ),
            ),
            const Text('Jam mengikuti zona waktu perangkat Anda.'),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                if (!_form.currentState!.validate()) return;
                if (_time == null || !_time!.isAfter(DateTime.now())) {
                  setState(
                    () => _error = 'Pilih waktu pertemuan yang belum berlalu.',
                  );
                  return;
                }
                Navigator.pop(context, (
                  location: _location.text.trim(),
                  scheduledAt: _time!,
                ));
              },
              child: const Text('Kirim usulan pertemuan'),
            ),
          ],
        ),
      ),
    ),
  );
}
