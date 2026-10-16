# Đọc nhanh mà vẫn hiểu

Đọc nhanh không có nghĩa là đọc ẩu. Khi gặp một tài liệu dài, người đọc thường lướt qua những từ quen thuộc và dừng lại ở những chỗ có thông tin mới. Máy tính có thể giúp việc đó bằng cách làm mờ các từ dễ đoán và giữ nguyên màu của những từ khó đoán.

Một trang tài liệu có thói quen riêng của nó. Nếu một cụm từ lặp lại nhiều lần thì đến lần thứ hai, lần thứ ba, người đọc đã biết trước nó sẽ xuất hiện. Vì vậy cụm từ đó không cần sáng nữa. Ngược lại, một con số lạ, một cái tên mới hay một ý bất ngờ sẽ đáng được chú ý hơn cả.

Cách làm này không cần tải mô hình ngôn ngữ nào. Chương trình chỉ đếm các từ trong chính trang đang đọc, rồi so sánh với những gì nó đã thấy ở các câu trước. Từ nào xuất hiện ít và khó đoán thì được giữ lại, từ nào xuất hiện nhiều và dễ đoán thì được làm mờ đi.

Với tiếng Việt, mỗi âm tiết được tính như một từ. Cách tính này đơn giản, nhưng đủ để cho thấy đâu là phần mở đầu quen thuộc và đâu là phần mới của một bài viết. Khi trang quá ngắn, chương trình không làm gì cả, vì không có đủ dữ liệu để biết điều gì là bất ngờ.

Người đọc luôn có thể tắt chế độ này bằng một phím bấm, và trang sẽ trở về đúng như lúc đầu, từng chữ một.
