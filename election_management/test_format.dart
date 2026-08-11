import 'package:nepali_date_picker/nepali_date_picker.dart';

void main() {
  final dt = NepaliDateTime.now();
  try {
    print(NepaliDateFormat('MMM dd, yyyy  hh:mm a').format(dt));
    print('Success');
  } catch (e) {
    print('Error: $e');
  }
}
