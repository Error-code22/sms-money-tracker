package com.droner.sms_money_tracker

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.UUID

class SmsDbHelper(context: Context) : SQLiteOpenHelper(context, "sms_money.db", null, 3) {
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE transactions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                sms_id TEXT UNIQUE NOT NULL,
                sender TEXT,
                body TEXT,
                amount REAL NOT NULL,
                currency TEXT,
                type TEXT NOT NULL,
                counterparty TEXT,
                ts INTEGER NOT NULL,
                is_confident INTEGER NOT NULL DEFAULT 0,
                category TEXT,
                interest REAL,
                shape TEXT,
                source TEXT NOT NULL DEFAULT 'sms',
                note TEXT
            )
            """.trimIndent()
        )
        db.execSQL("CREATE INDEX idx_ts ON transactions(ts)")
        db.execSQL(
            """
            CREATE TABLE learned_shapes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                sender TEXT NOT NULL,
                shape TEXT NOT NULL,
                UNIQUE(sender, shape)
            )
            """.trimIndent()
        )
        db.execSQL(
            """
            CREATE TABLE rejected_shapes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                sender TEXT NOT NULL,
                shape TEXT NOT NULL,
                UNIQUE(sender, shape)
            )
            """.trimIndent()
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2) {
            db.execSQL("ALTER TABLE transactions ADD COLUMN is_confident INTEGER NOT NULL DEFAULT 0")
            db.execSQL("ALTER TABLE transactions ADD COLUMN category TEXT")
            db.execSQL("ALTER TABLE transactions ADD COLUMN interest REAL")
            db.execSQL("ALTER TABLE transactions ADD COLUMN shape TEXT")
            db.execSQL(
                """
                CREATE TABLE learned_shapes (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    sender TEXT NOT NULL,
                    shape TEXT NOT NULL,
                    UNIQUE(sender, shape)
                )
                """.trimIndent()
            )
            db.execSQL(
                """
                CREATE TABLE rejected_shapes (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    sender TEXT NOT NULL,
                    shape TEXT NOT NULL,
                    UNIQUE(sender, shape)
                )
                """.trimIndent()
            )
        }
        if (oldVersion < 3) {
            db.execSQL("ALTER TABLE transactions ADD COLUMN source TEXT NOT NULL DEFAULT 'sms'")
            db.execSQL("ALTER TABLE transactions ADD COLUMN note TEXT")
        }
    }
}

object SmsDb {
    @Volatile
    private var helper: SmsDbHelper? = null

    private fun db(context: Context): SQLiteDatabase =
        (helper ?: synchronized(this) {
            helper ?: SmsDbHelper(context.applicationContext).also { helper = it }
        }).writableDatabase

    fun insert(context: Context, txn: Txn): Boolean {
        val database = db(context)
        val shape = SmsParser.shapeOf(txn.body)

        if (isRejected(database, txn.sender, shape)) return false

        val confident = txn.isConfident || isLearned(database, txn.sender, shape)

        val values = ContentValues().apply {
            put("sms_id", txn.smsId.toString())
            put("sender", txn.sender)
            put("body", txn.body)
            put("amount", txn.amount)
            put("currency", txn.currency)
            put("type", txn.type)
            put("counterparty", txn.counterparty)
            put("ts", txn.ts)
            put("is_confident", if (confident) 1 else 0)
            put("category", txn.category)
            put("interest", txn.interest)
            put("shape", shape)
        }
        return database.insertWithOnConflict(
            "transactions", null, values, SQLiteDatabase.CONFLICT_IGNORE
        ) != -1L
    }

    fun confirmTransaction(context: Context, id: Long): Int {
        val database = db(context)
        val row = fetchSenderAndShape(database, id) ?: return 0

        val learned = ContentValues().apply {
            put("sender", row.first)
            put("shape", row.second)
        }
        database.insertWithOnConflict(
            "learned_shapes", null, learned, SQLiteDatabase.CONFLICT_IGNORE
        )

        val update = ContentValues().apply { put("is_confident", 1) }
        return database.update(
            "transactions", update,
            "sender = ? AND shape = ?",
            arrayOf(row.first, row.second)
        )
    }

    fun markNotMoney(context: Context, id: Long): Int {
        val database = db(context)
        val row = fetchSenderAndShape(database, id) ?: return 0

        val rejected = ContentValues().apply {
            put("sender", row.first)
            put("shape", row.second)
        }
        database.insertWithOnConflict(
            "rejected_shapes", null, rejected, SQLiteDatabase.CONFLICT_IGNORE
        )

        return database.delete(
            "transactions",
            "sender = ? AND shape = ?",
            arrayOf(row.first, row.second)
        )
    }

    private fun fetchSenderAndShape(database: SQLiteDatabase, id: Long): Pair<String, String>? {
        val c = database.query(
            "transactions",
            arrayOf("sender", "shape"),
            "id = ?",
            arrayOf(id.toString()),
            null, null, null
        )
        c.use {
            if (!it.moveToFirst()) return null
            val sender = it.getString(0) ?: ""
            val shape = it.getString(1) ?: ""
            if (sender.isEmpty() || shape.isEmpty()) return null
            return Pair(sender, shape)
        }
    }

    private fun isLearned(database: SQLiteDatabase, sender: String, shape: String): Boolean {
        val c = database.query(
            "learned_shapes", arrayOf("id"),
            "sender = ? AND shape = ?", arrayOf(sender, shape),
            null, null, null, "1"
        )
        c.use { return it.moveToFirst() }
    }

    private fun isRejected(database: SQLiteDatabase, sender: String, shape: String): Boolean {
        val c = database.query(
            "rejected_shapes", arrayOf("id"),
            "sender = ? AND shape = ?", arrayOf(sender, shape),
            null, null, null, "1"
        )
        c.use { return it.moveToFirst() }
    }

    fun insertManual(
        context: Context,
        type: String,
        amount: Double,
        currency: String,
        category: String?,
        counterparty: String,
        ts: Long,
        note: String
    ): Long {
        val values = ContentValues().apply {
            put("sms_id", "manual-${System.currentTimeMillis()}-${UUID.randomUUID()}")
            put("sender", "")
            put("body", note)
            put("amount", amount)
            put("currency", currency)
            put("type", if (type == "credit") "credit" else "debit")
            put("counterparty", counterparty)
            put("ts", ts)
            put("is_confident", 1)
            if (category.isNullOrEmpty()) putNull("category") else put("category", category)
            putNull("interest")
            putNull("shape")
            put("source", "manual")
            put("note", note)
        }
        return db(context).insertWithOnConflict(
            "transactions", null, values, SQLiteDatabase.CONFLICT_IGNORE
        )
    }

    fun updateTransaction(
        context: Context,
        id: Long,
        type: String,
        amount: Double,
        currency: String,
        category: String?,
        counterparty: String,
        ts: Long,
        note: String?
    ): Int {
        val values = ContentValues().apply {
            put("type", if (type == "credit") "credit" else "debit")
            put("amount", amount)
            put("currency", currency)
            put("counterparty", counterparty)
            put("ts", ts)
            if (category.isNullOrEmpty()) putNull("category") else put("category", category)
            if (note != null) {
                put("note", note)
                put("body", note)
            }
        }
        return db(context).update("transactions", values, "id = ?", arrayOf(id.toString()))
    }

    fun setNote(context: Context, id: Long, note: String?): Int {
        val values = ContentValues()
        if (note.isNullOrEmpty()) values.putNull("note") else values.put("note", note)
        return db(context).update("transactions", values, "id = ?", arrayOf(id.toString()))
    }

    fun getTopCounterparties(context: Context, months: Int): String {
        val since = if (months <= 0) {
            0L
        } else {
            System.currentTimeMillis() - months * 30L * 24 * 3600 * 1000
        }
        val c = db(context).rawQuery(
            "SELECT counterparty, currency, SUM(amount) AS total, COUNT(*) AS cnt " +
                "FROM transactions WHERE type = 'debit' AND is_confident = 1 AND counterparty != '' " +
                "AND (ts >= ? OR ? = 0) GROUP BY counterparty, currency " +
                "ORDER BY total DESC LIMIT 10",
            arrayOf(since.toString(), since.toString())
        )
        val arr = JSONArray()
        c.use {
            while (c.moveToNext()) {
                arr.put(
                    JSONObject().apply {
                        put("counterparty", c.getString(0))
                        put("currency", c.getString(1) ?: "")
                        put("total", c.getDouble(2))
                        put("count", c.getInt(3))
                    }
                )
            }
        }
        return arr.toString()
    }

    fun getTransactions(context: Context, filter: String, query: String): String {
        val where = StringBuilder("1=1")
        val args = mutableListOf<String>()
        when (filter) {
            "debit" -> where.append(" AND type = 'debit'")
            "credit" -> where.append(" AND type = 'credit'")
            "review" -> where.append(" AND is_confident = 0")
        }
        if (query.isNotBlank()) {
            where.append(" AND (body LIKE ? OR counterparty LIKE ? OR sender LIKE ?)")
            val like = "%$query%"
            args.add(like)
            args.add(like)
            args.add(like)
        }
        val c = db(context).query(
            "transactions",
            null,
            where.toString(),
            args.toTypedArray(),
            null,
            null,
            "ts DESC",
            "500"
        )
        val arr = JSONArray()
        c.use {
            while (c.moveToNext()) {
                arr.put(
                    JSONObject().apply {
                        put("id", c.getLong(c.getColumnIndexOrThrow("id")))
                        put("sender", c.getString(c.getColumnIndexOrThrow("sender")) ?: "")
                        put("body", c.getString(c.getColumnIndexOrThrow("body")) ?: "")
                        put("amount", c.getDouble(c.getColumnIndexOrThrow("amount")))
                        put("currency", c.getString(c.getColumnIndexOrThrow("currency")) ?: "")
                        put("type", c.getString(c.getColumnIndexOrThrow("type")))
                        put("counterparty", c.getString(c.getColumnIndexOrThrow("counterparty")) ?: "")
                        put("ts", c.getLong(c.getColumnIndexOrThrow("ts")))
                        put("is_confident", c.getInt(c.getColumnIndexOrThrow("is_confident")))
                        put("category", c.getString(c.getColumnIndexOrThrow("category")) ?: "")
                        put("interest", if (c.isNull(c.getColumnIndexOrThrow("interest"))) JSONObject.NULL else c.getDouble(c.getColumnIndexOrThrow("interest")))
                        put("source", c.getString(c.getColumnIndexOrThrow("source")) ?: "sms")
                        put("note", c.getString(c.getColumnIndexOrThrow("note")) ?: "")
                    }
                )
            }
        }
        return arr.toString()
    }

    fun getSummary(context: Context): String {
        val database = db(context)
        val headline = headlineCurrency(database)
        val monthStart = startOfMonth(System.currentTimeMillis())

        val others = JSONArray()
        database.rawQuery(
            "SELECT currency, COUNT(*) AS cnt, " +
                "SUM(CASE WHEN type='debit' THEN amount ELSE 0 END) AS debit, " +
                "SUM(CASE WHEN type='credit' THEN amount ELSE 0 END) AS credit " +
                "FROM transactions WHERE currency != ? GROUP BY currency ORDER BY cnt DESC",
            arrayOf(headline)
        ).use { c ->
            while (c.moveToNext()) {
                others.put(
                    JSONObject().apply {
                        put("currency", c.getString(0))
                        put("count", c.getInt(1))
                        put("debit", c.getDouble(2))
                        put("credit", c.getDouble(3))
                    }
                )
            }
        }

        return JSONObject().apply {
            put("currency", headline)
            put("spentThisMonth", sumBy(context, "debit", monthStart, headline))
            put("receivedThisMonth", sumBy(context, "credit", monthStart, headline))
            put("spentTotal", sumBy(context, "debit", 0L, headline))
            put("receivedTotal", sumBy(context, "credit", 0L, headline))
            put("others", others)
        }.toString()
    }

    fun getMonthlyTotals(context: Context, months: Int): String {
        val headline = headlineCurrency(db(context))
        val arr = JSONArray()
        val cal = Calendar.getInstance()
        for (i in months - 1 downTo 0) {
            val start = startOfMonth(cal.timeInMillis)
            val end = start + 32L * 24 * 3600 * 1000
            val monthKey = "%04d-%02d".format(cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1)
            arr.put(
                JSONObject().apply {
                    put("month", monthKey)
                    put("spent", sumBetween(context, "debit", start, end, headline))
                    put("received", sumBetween(context, "credit", start, end, headline))
                }
            )
            cal.add(Calendar.MONTH, -1)
        }
        return arr.toString()
    }

    fun exportCsv(context: Context): String {
        val c = db(context).query("transactions", null, null, null, null, null, "ts ASC")
        val dateFmt = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)
        val sb = StringBuilder()
        sb.append("date,type,amount,currency,category,counterparty,sender,body,confident\n")
        c.use {
            while (c.moveToNext()) {
                val row = listOf(
                    dateFmt.format(Date(c.getLong(c.getColumnIndexOrThrow("ts")))),
                    c.getString(c.getColumnIndexOrThrow("type")),
                    c.getDouble(c.getColumnIndexOrThrow("amount")).toString(),
                    c.getString(c.getColumnIndexOrThrow("currency")),
                    c.getString(c.getColumnIndexOrThrow("category")),
                    c.getString(c.getColumnIndexOrThrow("counterparty")),
                    c.getString(c.getColumnIndexOrThrow("sender")),
                    c.getString(c.getColumnIndexOrThrow("body")),
                    if (c.getInt(c.getColumnIndexOrThrow("is_confident")) == 1) "yes" else "no"
                )
                sb.append(row.joinToString(",") { csvEscape(it) }).append('\n')
            }
        }

        val stamp = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date())
        val fileName = "money-tracker-export-$stamp.csv"
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, "text/csv")
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            }
            val uri = context.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            if (uri == null) {
                writeToAppFiles(context, fileName, sb.toString())
            } else {
                val stream = context.contentResolver.openOutputStream(uri)
                if (stream == null) {
                    writeToAppFiles(context, fileName, sb.toString())
                } else {
                    stream.use { it.write(sb.toString().toByteArray()) }
                    "Downloads/$fileName"
                }
            }
        } else {
            writeToAppFiles(context, fileName, sb.toString())
        }
    }

    private fun csvEscape(field: String?): String {
        val s = field ?: ""
        return if (s.any { it == ',' || it == '"' || it == '\n' || it == '\r' }) {
            "\"${s.replace("\"", "\"\"")}\""
        } else {
            s
        }
    }

    private fun writeToAppFiles(context: Context, fileName: String, content: String): String {
        val dir = context.getExternalFilesDir(null) ?: context.filesDir
        val file = File(dir, fileName)
        file.writeText(content)
        return file.absolutePath
    }

    private fun headlineCurrency(database: SQLiteDatabase): String {
        val c = database.rawQuery(
            "SELECT currency FROM transactions WHERE currency != '' GROUP BY currency " +
                "ORDER BY COUNT(*) DESC LIMIT 1",
            null
        )
        c.use { if (it.moveToFirst()) return it.getString(0) }
        return "KES"
    }

    private fun startOfMonth(time: Long): Long {
        val cal = Calendar.getInstance().apply { timeInMillis = time }
        cal.set(Calendar.DAY_OF_MONTH, 1)
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        return cal.timeInMillis
    }

    private fun sumBy(context: Context, type: String, since: Long, currency: String): Double {
        val where = if (since > 0) {
            "type = ? AND currency = ? AND ts >= ?"
        } else {
            "type = ? AND currency = ?"
        }
        val args = if (since > 0) {
            arrayOf(type, currency, since.toString())
        } else {
            arrayOf(type, currency)
        }
        val c = db(context).rawQuery(
            "SELECT COALESCE(SUM(amount), 0) AS total FROM transactions WHERE $where", args
        )
        c.use { it.moveToFirst(); return it.getDouble(0) }
    }

    private fun sumBetween(
        context: Context, type: String, start: Long, end: Long, currency: String
    ): Double {
        val c = db(context).rawQuery(
            "SELECT COALESCE(SUM(amount), 0) AS total FROM transactions " +
                "WHERE type = ? AND currency = ? AND ts >= ? AND ts < ?",
            arrayOf(type, currency, start.toString(), end.toString())
        )
        c.use { it.moveToFirst(); return it.getDouble(0) }
    }
}
