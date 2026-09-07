class ReceiptInfoData {
  final int? storeId;
  final int? organizationId;
  final String? nameAr;
  final String? nameEn;
  final String? addressText;
  final String? vatNumber;
  final String? crNumber;
  final int? logoResourceId;
  final String? unpaidInvoiceTitle;
  final String? paidInvoiceTitle;

  const ReceiptInfoData({
    this.storeId,
    this.organizationId,
    this.nameAr,
    this.nameEn,
    this.addressText,
    this.vatNumber,
    this.crNumber,
    this.logoResourceId,
    this.unpaidInvoiceTitle,
    this.paidInvoiceTitle,
  });

  factory ReceiptInfoData.fromJson(Map<String, dynamic> json) => ReceiptInfoData(
        storeId: json['storeId'] == null ? null : (json['storeId'] as num).toInt(),
        organizationId: json['organizationId'] == null
            ? null
            : (json['organizationId'] as num).toInt(),
        nameAr: json['nameAr'] as String?,
        nameEn: json['nameEn'] as String?,
        addressText: json['addressText'] as String?,
        vatNumber: json['vatNumber'] as String?,
        crNumber: json['crNumber'] as String?,
        logoResourceId: json['logoResourceId'] == null
            ? null
            : (json['logoResourceId'] as num).toInt(),
        unpaidInvoiceTitle: json['unpaidInvoiceTitle'] as String?,
        paidInvoiceTitle: json['paidInvoiceTitle'] as String?,
      );
}
